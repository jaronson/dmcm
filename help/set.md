$ dmcm set <service> { loglevel } { =, to } <value>
=======

DESCRIPTION
-------
  Set the value of a given service resource.

EXAMPLES
-------
  To set the dispatcher loglevel:
    $ dmcm set dispatcher loglevel=debug

  To set all services loglevel:
    $  dmcm set all loglevel to debug
