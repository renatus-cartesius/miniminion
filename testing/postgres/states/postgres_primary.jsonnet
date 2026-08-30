local Resource(type, args={}, deps=[]) = { deps: deps, type: type, } + args;

{
  postgresql:
    Resource('apt_pkg', { name: 'postgresql' }),

  postgresql_conf:
    Resource('file', {
      path: '/etc/postgresql/16/main/postgresql.conf',
      content: |||
        data_directory = '/var/lib/postgresql/16/main'
        listen_addresses = '*'
        port = 5432
        wal_level = replica
        max_wal_senders = 3
        wal_keep_size = 256
        hot_standby = on
      |||,
      mode: '0644',
    }, deps=['postgresql']),

  pg_hba_conf:
    Resource('file', {
      path: '/etc/postgresql/16/main/pg_hba.conf',
      content: |||
        local   all             all                                     peer
        host    all             all             127.0.0.1/32            scram-sha-256
        host    all             all             192.168.56.0/24         scram-sha-256
        host    replication     replicator      192.168.56.0/24         scram-sha-256
      |||,
      mode: '0640',
    }, deps=['postgresql']),

  postgresql_service:
    Resource('service', {
      name: 'postgresql',
      state: 'restarted',
      enabled: true,
    }, deps=['postgresql_conf', 'pg_hba_conf']),

  create_replicator_user:
    Resource('shell', {
      command: |||
        su - postgres -c "psql -c \"SELECT 1 FROM pg_roles WHERE rolname='replicator'\" | grep -q 1" ||
        su - postgres -c "psql -c \"CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_secret'\""
      |||,
      output_name: 'replicator_created',
    }, deps=['postgresql_service']),
}