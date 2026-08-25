{
  agents: {
    "master-01": {
      state: "state_master.jsonnet",
      depends: [],
    },
    "master-02": {
      state: "state_master.jsonnet",
      depends: [],
    },
    "worker-01": {
      state: "state_worker.jsonnet",
      depends: ["master-01", "master-02"],
    },
    "worker-02": {
      state: "state_worker.jsonnet",
      depends: ["master-01", "master-02"],
    },
  },
}