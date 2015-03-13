Lithium
=======

Lithium is a Selenium Grid replacement, that instead of fully proxying sessions, Lithium
will forward the client onto the session node, relieving timing and locking issues.

INSTALLATION
------------

To install this module, run the following commands:

	perl Makefile.PL
	make
	make test
	make install

SUPPORT AND DOCUMENTATION
-------------------------

After installing, you can find documentation for this module with the
perldoc command.

	perldoc $(which lithium)
	perldoc Lithium
	perldoc Lithium::Cache
	perldoc Lithium::Daemon

For bug fixes and feature requests please submit a ticket with the
[Github Repo](https://github.com/GrayTShirt/Lithium)

License and Copyright
---------------------

Copyright 2015 by Dan Molik <dmolik@synacor.com>

Under the GNU GPL v3 License, see the included LICENSE file for details.
