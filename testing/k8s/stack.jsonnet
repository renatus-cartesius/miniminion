{
  agents: {
    'master-01': { state: 'states/kubernetes_master.jsonnet', depends: [] },
    'master-02': { state: 'states/kubernetes_master.jsonnet', depends: ['master-01'] },
    'master-03': { state: 'states/kubernetes_master.jsonnet', depends: ['master-01'] },
    'worker-01': { state: 'states/kubernetes_worker.jsonnet', depends: ['master-01', 'master-02', 'master-03'] },
    'worker-02': { state: 'states/kubernetes_worker.jsonnet', depends: ['master-01', 'master-02', 'master-03'] },
    'worker-03': { state: 'states/kubernetes_worker.jsonnet', depends: ['master-01', 'master-02', 'master-03'] },
  },
}