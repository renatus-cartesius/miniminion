local Resource(type, args={}, deps=[]) = { deps: deps, type: type, } + args;

local has_apt = std.length(std.native('shellExec')('which apt-get')) > 0;
local has_apk = std.length(std.native('shellExec')('which apk')) > 0;
local has_dnf = std.length(std.native('shellExec')('which dnf')) > 0;

{
  postgresql:
    if has_apt then
      Resource('apt_pkg', { name: 'postgresql' })
    else if has_dnf then
      Resource('dnf_pkg', { name: 'postgresql-server' })
    else
      Resource('apk_pkg', { name: 'postgresql16' }),

  stop_postgres:
    Resource('shell', {
      command: 'systemctl stop postgresql 2>/dev/null; systemctl stop postgresql-16 2>/dev/null; pg_lsclusters 2>/dev/null | grep -q . && pg_dropcluster 16 main --stop || true',
    }, deps=['postgresql']),

  clear_data:
    Resource('shell', {
      command: 'rm -rf /var/lib/postgresql/16/main && rm -rf /var/lib/postgresql/data && mkdir -p /var/lib/postgresql/16/main',
    }, deps=['stop_postgres']),

  pg_basebackup:
    Resource('shell', {
      command: |||
        cat /root/.ssh/vagrant_ecdsa > /var/lib/postgresql/.ssh/id_ecdsa
        chmod 600 /var/lib/postgresql/.ssh/id_ecdsa
        chown -R postgres:postgres /var/lib/postgresql/.ssh
        su - postgres -c "pg_basebackup -h 192.168.56.41 -D /var/lib/postgresql/16/main -U replicator -P -v --wal-method=stream"
        touch /var/lib/postgresql/16/main/standby.signal
      |||,
    }, deps=['clear_data']),

  postgresql_conf:
    Resource('file', {
      path: '/etc/postgresql/16/main/postgresql.conf',
      content: |||
        data_directory = '/var/lib/postgresql/16/main'
        port = 5432
        hot_standby = on
        primary_conninfo = 'host=192.168.56.41 port=5432 user=replicator password=repl_secret'
      |||,
      mode: '0644',
    }, deps=['pg_basebackup']),

  start_postgres:
    Resource('service', {
      name: if has_apt then 'postgresql' else 'postgresql-16',
      state: 'restarted',
      enabled: true,
    }, deps=['postgresql_conf']),
}