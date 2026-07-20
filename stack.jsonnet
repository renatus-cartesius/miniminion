{
  agents: {
    "master-01": {
      state: "kubernetes_master.jsonnet",
      depends: [],
    },
    "worker-01": {
      state: "kubernetes_worker.jsonnet",
      depends: ["master-01"],
    },
  },
}