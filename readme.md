# UC Local APEX Dev

**Have a 23ai with APEX and ORDS running in a few minutes**

This set of scripts aims to make developing APEX on your local machine as easy as possible. It is a ready-to-use setup with common tasks automated as bash scripts.

## Features

- ✅ Create users and workspaces with optimal settings with a single command
- ✅ All users are stored for easy access with SQLcl or VS Code SQL Developer
- ✅ Easily delete all data to test installation scripts multiple times
- ✅ Backup and restore your data, workspaces and apps
- ✅ Run ORDS with SSL
- ✅ Test APEX application installs
- ✅ VS Code SQL Developer debugger support

**This is not for production use!** The environment is configured to be unsecure to make development as easy as possible.

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
- Tim Hall for the [drop_all.sql](https://oracle-base.com/dba/script?category=miscellaneous&file=drop_all.sql) script
- Philipp Salvisberg for [helping me to figure out how to use the debugger](https://gist.github.com/PhilippSalvisberg/2f2853bc7a95fa86d9de9c0deab10602)
- Scott Spendolini for his blog post on [how to add self-signed certificates to ORDS](https://spendolini.blog/adding-ssl-to-your-ords-container)
- Matt Mulvaney for his blog post on [unexpiring ORDS accounts](https://mattmulvaney.hashnode.dev/unexpiring-the-ordspublicuser-user-for-apex)
- The database team for providing an ARM image for the Oracle database
- The ORDS team for providing an ARM image for ORDS

The cherry on top would be Oracle making APEX patches free to download for everyone.
