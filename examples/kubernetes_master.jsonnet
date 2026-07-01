// Example: Kubernetes master node setup on Ubuntu 24.04
// Uses containerd runtime, kubeadm, and flannel CNI.

local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

local fileMode(mode) =
  local digits = std.stringChars(mode);
  std.foldl(function(acc, digit) acc * 8 + std.parseInt(digit), digits, 0);

local shellExec = std.native('shellExec');

// Guard checks
local apt_updated = shellExec('[ -f /root/.apt-updated ] && echo -n updated || true');
local swap_on = shellExec('swapon --show | wc -l');
local k8s_repo_added = shellExec('[ -f /etc/apt/sources.list.d/k8s.list ] && echo -n yes || true');
local cluster_init = shellExec('[ -f /etc/kubernetes/admin.conf ] && echo -n yes || true');

// ---------- Phase 1: System preconditions ----------
(if apt_updated != 'updated' then {
  apt_update: Resource('shell', {
    command: 'apt-get update && apt-get install -y curl && touch /root/.apt-updated',
  }),
} else {})

+

(if swap_on != '0' then {
  disable_swap: Resource('shell', {
    command: 'swapoff -a && sed -i "/ swap /d" /etc/fstab',
  }),
} else {})

+

// ---------- Phase 2: Kernel modules + sysctl ----------
{
  kernel_modules: Resource('shell', {
    command: 'modprobe overlay; modprobe br_netfilter',
  }),

  sysctl_conf: Resource('file', {
    path: '/etc/sysctl.d/k8s.conf',
    content: 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n',
    mode: fileMode('644'),
  }, deps=['kernel_modules']),

  sysctl_apply: Resource('shell', {
    command: 'sysctl --system',
  }, deps=['sysctl_conf']),
}

+

// ---------- Phase 3: Containerd from default repos ----------
(if apt_updated == 'updated' then {
  containerd: Resource('package', {name: 'containerd'}),
} else {
  containerd: Resource('package', {name: 'containerd'}, deps=['apt_update']),
})

+

{
  containerd_config: Resource('shell', {
    command: 'mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml && sed -i "s|SystemdCgroup = false|SystemdCgroup = true|" /etc/containerd/config.toml && systemctl restart containerd && systemctl enable containerd',
  }, deps=['containerd']),
}

+

// ---------- Phase 4: k8s repo + tools ----------
(if k8s_repo_added != 'yes' then {
  k8s_repo: Resource('shell', {
    command: |||
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key -o /etc/apt/keyrings/k8s.asc
      echo 'deb [signed-by=/etc/apt/keyrings/k8s.asc] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' > /etc/apt/sources.list.d/k8s.list
      apt-get update
    |||,
  }, deps=['containerd_config']),
} else {})

+

{
  kubeadm: Resource('package', {name: 'kubeadm'}, deps=(if k8s_repo_added != 'yes' then ['k8s_repo'] else [])),
  kubelet: Resource('package', {name: 'kubelet'}, deps=(if k8s_repo_added != 'yes' then ['k8s_repo'] else [])),
  kubectl: Resource('package', {name: 'kubectl'}, deps=(if k8s_repo_added != 'yes' then ['k8s_repo'] else [])),

  hold_k8s_pkgs: Resource('shell', {
    command: 'apt-mark hold kubeadm kubelet kubectl',
  }, deps=['kubeadm', 'kubelet', 'kubectl']),
}

+

// ---------- Phase 5: kubeadm init ----------
(if cluster_init != 'yes' then {
  kubeadm_init: Resource('shell', {
    command: 'kubeadm init --pod-network-cidr=10.244.0.0/16 --skip-phases=addon/kube-proxy',
  }, deps=['containerd_config', 'hold_k8s_pkgs', 'sysctl_apply'] + (if swap_on != '0' then ['disable_swap'] else [])),
} else {})

+

// ---------- Phase 6: Post-init ----------
{
  kubeconfig: Resource('shell', {
    command: 'mkdir -p /root/.kube && cp -i /etc/kubernetes/admin.conf /root/.kube/config 2>/dev/null; chown root:root /root/.kube/config 2>/dev/null',
  }, deps=(if cluster_init != 'yes' then ['kubeadm_init'] else [])),

  flannel_cni: Resource('shell', {
    command: 'kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml',
  }, deps=['kubeconfig']),

  master_ready: Resource('shell', {
    command: 'kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null; kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide',
  }, deps=['flannel_cni']),
}