# UC Local APEX Dev

**Get Oracle 26ai with APEX and ORDS running in minutes. Automate the tedious parts of local APEX development.**

A containerized development environment (works with Docker, Podman, or any container runtime) that automates common tasks and lets you focus on building APEX applications.

## Features

Everything is a single command via the `local-26ai.sh` wrapper — run `local-26ai.sh --help` or see the [Command Reference](https://www.united-codes.com/products/uc-local-apex-dev/docs/reference/commands/) for the full list.

- ✅ [One-command operations](https://www.united-codes.com/products/uc-local-apex-dev/docs/reference/commands/): create users, backups, clear schemas, test installs
- ✅ [Create APEX workspaces and database schemas](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/creating-users/) with optimal development grants
- ✅ All users automatically registered in SQLcl and VS Code for instant access
- ✅ [Built-in Oracle DataPump backup and restore](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/backups/)
- ✅ [ORDS with SSL support](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/common-tasks/#ssl-configuration) for production-like local development
- ✅ [Test APEX application installs](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/install-apps-scripts/) repeatedly in isolated test schemas
- ✅ [Full PL/SQL debugging support](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/plsql-debugging/) with VS Code SQL Developer
- ✅ Disk-space tooling for the 12GB Free edition: usage report, shrink, and Advanced Compression

**⚠️ This is not for production use!** Intentionally unsecure and optimized for ease of development. Passwords stored in plain text, security features relaxed. For local development only.

[Installation Guide](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/)

## Documentation

For complete setup instructions, configuration guides, and usage examples, visit our documentation site:

**📖 [UC Local APEX Dev Documentation](https://www.united-codes.com/products/uc-local-apex-dev/docs/)**

The documentation includes:
- [Installation Guide](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/)
- [Common Tasks & Commands](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/common-tasks/)
- [Backups](https://www.united-codes.com/products/uc-local-apex-dev/docs/getting-started/backups/)
- [Migration Guides](https://www.united-codes.com/products/uc-local-apex-dev/docs/migrations/25-3/)

## Contributing

If you have any ideas on how to improve this setup, please create an issue or a pull request.

I am especially thankful for improvements to the bash scripts.


## Special thanks

- The [contributors](https://github.com/United-Codes/uc-local-apex-dev/graphs/contributors) for their help
- Connor McDonald for his blog post on [space efficiently using the Free Edition](https://connor-mcdonald.com/2023/12/18/the-ultimate-database-free-edition/)
- Tim Hall for the [drop_all.sql](https://oracle-base.com/dba/script?category=miscellaneous&file=drop_all.sql) script
- Philipp Salvisberg for [helping me to figure out how to use the debugger](https://gist.github.com/PhilippSalvisberg/2f2853bc7a95fa86d9de9c0deab10602)
- Scott Spendolini for his blog post on [how to add self-signed certificates to ORDS](https://spendolini.blog/adding-ssl-to-your-ords-container)
- Matt Mulvaney for his blog post on [unexpiring ORDS accounts](https://mattmulvaney.hashnode.dev/unexpiring-the-ordspublicuser-user-for-apex)
- The database team for providing an ARM image for the Oracle database
- The ORDS team for providing an ARM image for ORDS

The cherry on top would be Oracle making APEX patches free to download for everyone.
