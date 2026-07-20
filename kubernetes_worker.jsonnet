local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

{
  kubelet: Resource('apt_pkg', { name: 'kubelet' }),
  kubectl: Resource('apt_pkg', { name: 'kubectl' }, deps=['kubelet']),
  kubeadm: Resource('apt_pkg', { name: 'kubeadm' }, deps=['kubelet']),
  containerd: Resource('apt_pkg', { name: 'containerd.io' }, deps=['kubelet']),
  cni_plugins: Resource('apt_pkg', { name: 'kubernetes-cni' }, deps=['kubelet']),
  kubeadm_join: Resource('shell', { command: 'kubeadm join --token <token> <master-ip>:6443' }, deps=['kubeadm', 'containerd', 'cni_plugins']),
}