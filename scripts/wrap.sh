#!/usr/bin/env bash

set -e

source ./scripts/util/load_env.sh

if [ -z "$1" ]; then
  echo "Usage: $0 <file_name>"
  exit 1
fi

# If the input path is relative (doesn't start with /)
if [[ "${1}" != /* ]]; then
  # Make it absolute using the original working directory
  FILE_NAME=$(realpath "${ORIGINAL_PWD}/${1}")
else
  FILE_NAME="${1}"
fi

echo "Wrapping file $FILE_NAME"

# check if file exists
if [ ! -f "$FILE_NAME" ]; then
  echo "File $FILE_NAME not found"
  exit 1
fi

# if file extension is .pkb
if [[ $FILE_NAME == *.pkb ]]; then
  # replace .pkb with .pkw
  OUTPUT_FILE_NAME=$(echo $FILE_NAME | sed 's/.pkb/.pkw/')
else
  # add "_wrapped" to the file name
  EXTENSION="${FILE_NAME##*.}"
  WO_EXTENSION="${FILE_NAME%.*}"
  OUTPUT_FILE_NAME="${WO_EXTENSION}_wrapped.${EXTENSION}"
fi

FILE_CONTENT=$(cat $FILE_NAME)

# trim whitespace from the beginning and end of the file
# FILE_CONTENT=$(echo "$FILE_CONTENT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# if last char is /, remove it
#FILE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/\/$//')

# concat the file content with the wrapping code
CHUNKED_LOB=$(echo "$FILE_CONTENT" | awk '
  { 
    buf = buf $0 "\n"
    while (length(buf) > 32000) {
     

      printf "l_chunk :=  q'\''!%s!'\'';\n  dbms_lob.writeappend(l_source, length(l_chunk), l_chunk );\n", substr(buf, 1, 32000)
      buf = substr(buf, 32001)
    }
  }
  END {
    if (length(buf) > 0) printf "l_chunk :=  q'\''!%s!'\'';\n  dbms_lob.writeappend(l_source, length(l_chunk), l_chunk );\n", buf
  }
')

TMP_SQL_FILE=$(mktemp)

cat >"$TMP_SQL_FILE" <<EOSQL
set serveroutput on size unlimited
set feedback off
set define off
declare
  l_source  clob;
  l_wrap    clob;
  l_chunk   varchar2(32767);
  l_varchar2_tab dbms_sql.varchar2a;
  l_wrapped_tab  dbms_sql.varchar2a;
  l_chunk_size   constant pls_integer := 32000;
  l_offset       pls_integer := 1;
  l_piece        varchar2(32767);
  l_index        pls_integer := 1;
begin
  dbms_lob.createtemporary(l_source, true);

  ${CHUNKED_LOB}

  while l_offset <= dbms_lob.getlength(l_source) loop
    l_piece := dbms_lob.substr(l_source, l_chunk_size, l_offset);
    l_varchar2_tab(l_index) := l_piece;
    l_index := l_index + 1;
    l_offset := l_offset + l_chunk_size;
  end loop;

  l_wrapped_tab := dbms_ddl.wrap(
    ddl => l_varchar2_tab,
    lb => l_varchar2_tab.first,
    ub => l_varchar2_tab.last
  );

  dbms_lob.createtemporary(l_wrap, true);

  for i in l_wrapped_tab.first..l_wrapped_tab.last loop
    dbms_lob.writeappend(l_wrap, length(l_wrapped_tab(i)), l_wrapped_tab(i));
  end loop;

  dbms_output.put_line(l_wrap);

  dbms_lob.freetemporary(l_source);
  dbms_lob.freetemporary(l_wrap);
end;
/
EOSQL

# to debug:
cp "$TMP_SQL_FILE" ~/Downloads/tmp-shit.txt

WRAPPED_CODE=$(
  sql -noupdates -S -name $DB_CONN_NAME <"$TMP_SQL_FILE"
)

rm "$TMP_SQL_FILE"

# remove first line if it's empty
# WRAPPED_CODE=$(echo "$WRAPPED_CODE" | sed '/^$/{ 1d; }')

# add a "/" at the end of the wrapped code
#WRAPPED_CODE="${WRAPPED_CODE}"$'\n\n/'

echo "Writing wrapped code to $OUTPUT_FILE_NAME"
echo "$WRAPPED_CODE" >$OUTPUT_FILE_NAME
