{
  agents: {
    'master-01': {
      state: 'examples/kubernetes_master.jsonnet',
      depends: [],
    },
    'master-02': {
      state: 'examples/kubernetes_master.jsonnet',
      depends: ['master-01'],
    },
    'master-03': {
      state: 'examples/kubernetes_master.jsonnet',
      depends: ['master-01'],
    },
    'master-04': {
      state: 'examples/kubernetes_master.jsonnet',
      depends: ['master-01'],
    },
    'master-05': {
      state: 'examples/kubernetes_master.jsonnet',
      depends: ['master-01'],
    },
    'master-06': {
      state: 'examples/kubernetes_master.jsonnet',
      depends: ['master-01'],
    },
    'worker-01': {
      state: 'examples/kubernetes_worker.jsonnet',
      depends: ['master-01', 'master-02', 'master-03'],
    },
    'worker-02': {
      state: 'examples/kubernetes_worker.jsonnet',
      depends: ['master-01', 'master-02', 'master-03'],
    },
    'worker-03': {
      state: 'examples/kubernetes_worker.jsonnet',
      depends: ['master-01', 'master-02', 'master-03'],
    },
  },
}
