Usage
======

`dmcm [options] <action> <service> [resource] {=,to [value]}`

[options]
---------
`-d,--debug - Run in debug mode`
`-i,--interactive - Run in interactive mode`

<actions>
---------
  clear          echo           get
  page           restart        rm
  set            start          status
  stop           tail           view

<services>
----------
  api            assign         console
  dispatcher     km             monitor
  mysql          pound          publisher
  rabbitmq       riak           subscriber

[resources]
-----------
  credentials    loglevel       logs
  memusage       path           pid
  riak-members   riak-ring      runlogs
