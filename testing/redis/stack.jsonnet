{
  agents: {
    'sentinel-01': { state: 'states/redis_sentinel.jsonnet', depends: [] },
    'sentinel-02': { state: 'states/redis_sentinel.jsonnet', depends: ['sentinel-01'] },
    'sentinel-03': { state: 'states/redis_sentinel.jsonnet', depends: ['sentinel-01'] },
  },
}