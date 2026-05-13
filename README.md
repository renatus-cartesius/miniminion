# Miniminion (minim)

Simple pull-based(for now only for local running, without pulling state from the control plane) configurations management system (alternative for salt, puppet, chef, etc.). 

Minim uses jsonnet for declarative state description.

## TODO

- [ ] implement a fact-like mechanism in the state compilation runtime.
- [ ] add more relation types for resources (not only dependencies) such as "requires" in the saltstack.
- [ ] add a bpf sensors layer for tracking resources state by tracing some kernel events (for example running fexit for sys_write on a file, that controlled by the minim resource)
- [ ] implement a drift checker/watcher for resources and overall state, that utilizes sensors layer
