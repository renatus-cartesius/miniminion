{
  agents: {
    'pg-primary': { state: 'states/postgres_primary.jsonnet', depends: [] },
    'pg-replica': { state: 'states/postgres_replica.jsonnet', depends: ['pg-primary'] },
  },
}