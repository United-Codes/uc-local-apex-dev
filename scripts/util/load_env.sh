# check if .env is in the current directory or in the parent directory
export $(grep -v '^#' .env | xargs)

echo "loaded .env file"
