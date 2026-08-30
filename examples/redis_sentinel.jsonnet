local Resource(type, args={}, deps=[]) = { deps: deps, type: type, } + args;

{
  redis_server:
    Resource('apt_pkg', { name: 'redis-server' }),

  redis_conf:
    Resource('file', {
      path: '/etc/redis/redis.conf',
      content: |||
        bind 0.0.0.0
        port 6379
        daemonize no
        supervised systemd
        loglevel notice
        save 900 1
        save 300 10
        save 60 10000
        dbfilename dump.rdb
        dir /var/lib/redis
        appendonly yes
        appendfilename appendonly.aof
      |||,
      mode: '0640',
    }, deps=['redis_server']),

  redis_service:
    Resource('service', {
      name: 'redis-server',
      state: 'restarted',
      enabled: true,
    }, deps=['redis_conf']),

  redis_sentinel_conf:
    Resource('file', {
      path: '/etc/redis/sentinel.conf',
      content: |||
        port 26379
        daemonize no
        supervised systemd
        logfile /var/log/redis/sentinel.log
        sentinel monitor mymaster 192.168.56.31 6379 2
        sentinel down-after-milliseconds mymaster 5000
        sentinel failover-timeout mymaster 10000
        sentinel parallel-syncs mymaster 1
      |||,
      mode: '0640',
    }, deps=['redis_server']),

  redis_sentinel_service:
    Resource('service', {
      name: 'redis-sentinel@6379',
      state: 'restarted',
      enabled: true,
    }, deps=['redis_sentinel_conf']),
}