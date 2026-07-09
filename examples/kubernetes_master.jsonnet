// Example: Kubernetes master node setup on Ubuntu 24.04 and CentOS 9
// Uses containerd runtime, kubeadm, and flannel CNI.

local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

local shellExec = std.native('shellExec');

// Distro detection
local has_apt = shellExec('which apt-get >/dev/null 2>&1 && echo -n yes || true');
local has_dnf = shellExec('which dnf >/dev/null 2>&1 && echo -n yes || true');
local is_ubuntu = has_apt == 'yes';
local is_centos = has_dnf == 'yes';
local pkg_type = if is_ubuntu then 'apt_pkg' else 'dnf_pkg';

// Guard checks
local swap_on = shellExec('swapon --show | wc -l');
local k8s_apt_repo_added = shellExec('[ -f /etc/apt/sources.list.d/k8s.list ] && echo -n yes || true');
local k8s_rpm_repo_added = shellExec('[ -f /etc/yum.repos.d/kubernetes.repo ] && echo -n yes || true');
local cluster_init = shellExec('[ -f /etc/kubernetes/admin.conf ] && echo -n yes || true');
local api_server_ip = shellExec("ip -4 addr show | awk '/inet 192.168/{print $2}' | cut -d/ -f1 | head -1");

// ---------- Phase 1: System preconditions ----------
(if swap_on != '0' then {
   disable_swap: Resource('shell', {
     command: 'swapoff -a && sed -i "/ swap /d" /etc/fstab',
   }),
 } else {})

+

// ---------- Phase 2: Kernel modules + sysctl ----------
{
  kernel_modules: Resource('kernel_module', {
    modules: ['overlay', 'br_netfilter'],
  }),

  sysctl_setup: Resource('sysctl', {
    params: {
      'net.bridge.bridge-nf-call-iptables': '1',
      'net.bridge.bridge-nf-call-ip6tables': '1',
      'net.ipv4.ip_forward': '1',
    },
  }, deps=['kernel_modules']),
}

+

// ---------- Phase 3: Containerd ----------
(if is_centos then {
   docker_repo: Resource('shell', {
     command: 'yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true',
   }),
 } else {})

+

{
  containerd: Resource(pkg_type, {
    name: if is_ubuntu then 'containerd' else 'containerd.io',
  }, deps=(if is_centos then ['docker_repo'] else [])),

  containerd_config: Resource('shell', {
    command: if is_ubuntu then
      'mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml && sed -i "s|SystemdCgroup = false|SystemdCgroup = true|" /etc/containerd/config.toml'
    else
      'mkdir -p /etc/containerd && (containerd config default 2>/dev/null || true) > /etc/containerd/config.toml && sed -i "/^disabled_plugins/d; s|SystemdCgroup = false|SystemdCgroup = true|" /etc/containerd/config.toml',
  }, deps=['containerd']),

  containerd_service: Resource('service', {
    name: 'containerd',
    state: 'running',
    enabled: true,
  }, deps=['containerd_config']),
}

+

// ---------- Phase 4: k8s repo + tools ----------
(if is_ubuntu && k8s_apt_repo_added != 'yes' then {
   k8s_repo: Resource('apt_repo', {
     key_url: 'https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key',
     key_path: '/etc/apt/keyrings/k8s.asc',
     source: 'deb [signed-by=/etc/apt/keyrings/k8s.asc] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /',
     source_path: '/etc/apt/sources.list.d/k8s.list',
   }, deps=['containerd_service']),
 } else {})

+

(if is_centos && k8s_rpm_repo_added != 'yes' then {
   k8s_repo: Resource('shell', {
     command: 'printf "[kubernetes]\nname=Kubernetes\nbaseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/\nenabled=1\ngpgcheck=1\ngpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key\n" > /etc/yum.repos.d/kubernetes.repo',
   }, deps=['containerd_service']),
 } else {})

+

{
  kubeadm: Resource(pkg_type, { name: 'kubeadm' }, deps=(if is_ubuntu && k8s_apt_repo_added != 'yes' then ['k8s_repo'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['k8s_repo'] else [])),
  kubelet: Resource(pkg_type, { name: 'kubelet' }, deps=(if is_ubuntu && k8s_apt_repo_added != 'yes' then ['k8s_repo'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['k8s_repo'] else [])),
  kubectl: Resource(pkg_type, { name: 'kubectl' }, deps=(if is_ubuntu && k8s_apt_repo_added != 'yes' then ['k8s_repo'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['k8s_repo'] else [])),
}

+

// ---------- Phase 5: Hold k8s packages ----------
(if is_ubuntu then {
   hold_k8s_pkgs: Resource('shell', {
     command: 'apt-mark hold kubeadm kubelet kubectl',
   }, deps=['kubeadm', 'kubelet', 'kubectl']),
 } else {})

+

// ---------- Phase 6: kubeadm init ----------
(if cluster_init != 'yes' then {
   kubeadm_init: Resource('shell', {
     command: 'kubeadm init --pod-network-cidr=10.244.0.0/16 --skip-phases=addon/kube-proxy --apiserver-advertise-address=' + api_server_ip + ' --ignore-preflight-errors=NumCPU,Mem,CRI',
   }, deps=['containerd_service', 'sysctl_setup'] + (if swap_on != '0' then ['disable_swap'] else []) + (if is_ubuntu then ['hold_k8s_pkgs'] else ['kubeadm', 'kubelet', 'kubectl'])),
 } else {})

+

// ---------- Phase 7: Post-init ----------
{
  kubeconfig: Resource('shell', {
    command: 'mkdir -p /root/.kube && cp -i /etc/kubernetes/admin.conf /root/.kube/config 2>/dev/null; chown root:root /root/.kube/config 2>/dev/null && sleep 20',
  }, deps=(if cluster_init != 'yes' then ['kubeadm_init'] else [])),

  flannel_cni: Resource('shell', {
    command: 'kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml --validate=false',
  }, deps=['kubeconfig']),

  master_ready: Resource('shell', {
    command: 'kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null; kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide',
  }, deps=['flannel_cni']),
}
