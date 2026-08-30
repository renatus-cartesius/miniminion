local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

local shellExec = std.native('shellExec');

local has_apt = shellExec('which apt-get >/dev/null 2>&1 && echo -n yes || true');
local has_dnf = shellExec('which dnf >/dev/null 2>&1 && echo -n yes || true');
local is_ubuntu = has_apt == 'yes';
local is_centos = has_dnf == 'yes';
local pkg_type = if is_ubuntu then 'apt_pkg' else 'dnf_pkg';
local swap_on = shellExec('swapon --show | wc -l');

// ---------- Phase 1: System preconditions ----------
(if swap_on != '0' then {
   disable_swap: Resource('shell', {
     command: 'swapoff -a && sed -i "/ swap /d" /etc/fstab',
   }),
 } else {}) +

// ---------- Phase 2: Package cache update ----------
(if is_ubuntu then {
  update_cache: Resource('apt_update', {}, deps=(if swap_on != '0' then ['disable_swap'] else [])),
} else {
  update_cache: Resource('dnf_update', {}, deps=(if swap_on != '0' then ['disable_swap'] else [])),
}) +

// ---------- Phase 3: Kernel modules + sysctl ----------
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
} +

// ---------- Phase 4: Containerd ----------
(if is_centos then {
   docker_repo: Resource('shell', {
     command: 'yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true',
   }),
 } else {}) +

{
  containerd: Resource(pkg_type, {
    name: if is_ubuntu then 'containerd' else 'containerd.io',
  }, deps=(if is_centos then ['docker_repo'] else []) + ['update_cache']),

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
} +

// ---------- Phase 5: k8s repo + tools ----------
local k8s_apt_repo_added = shellExec('[ -f /etc/apt/sources.list.d/k8s.list ] && echo -n yes || true');
local k8s_rpm_repo_added = shellExec('[ -f /etc/yum.repos.d/kubernetes.repo ] && echo -n yes || true');

(if is_ubuntu && k8s_apt_repo_added != 'yes' then {
   k8s_repo: Resource('apt_repo', {
     key_url: 'https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key',
     key_path: '/etc/apt/keyrings/k8s.asc',
     source: 'deb [signed-by=/etc/apt/keyrings/k8s.asc] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /',
     source_path: '/etc/apt/sources.list.d/k8s.list',
   }, deps=['containerd_service']),
   repo_update: Resource('apt_update', {}, deps=['k8s_repo']),
 } else {}) +

(if is_centos && k8s_rpm_repo_added != 'yes' then {
   k8s_repo: Resource('shell', {
     command: 'printf "[kubernetes]\nname=Kubernetes\nbaseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/\nenabled=1\ngpgcheck=1\ngpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key\n" > /etc/yum.repos.d/kubernetes.repo',
   }, deps=['containerd_service']),
   repo_update: Resource('dnf_update', {}, deps=['k8s_repo']),
 } else {}) +

{
  kubeadm: Resource(pkg_type, { name: 'kubeadm' }, deps=['containerd_service'] + (if is_ubuntu && k8s_apt_repo_added != 'yes' then ['repo_update'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['repo_update'] else [])),
  kubelet: Resource(pkg_type, { name: 'kubelet' }, deps=['containerd_service'] + (if is_ubuntu && k8s_apt_repo_added != 'yes' then ['repo_update'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['repo_update'] else [])),
} +

// ---------- Phase 6: Join cluster ----------
{
  cluster_join: Resource('shell', {
    command: 'kubeadm join 192.168.56.11:6443 --token {{ ctx.global.k8s_token }} --discovery-token-ca-cert-hash sha256:{{ ctx.global.k8s_hash }} --ignore-preflight-errors=all 2>/dev/null; true',
  }, deps=['kubeadm', 'kubelet']),

  kubelet_start: Resource('service', {
    name: 'kubelet',
    state: 'running',
    enabled: true,
  }, deps=['cluster_join']),
}