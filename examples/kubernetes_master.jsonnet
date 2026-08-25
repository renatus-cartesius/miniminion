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

local already_init = shellExec('[ -f /etc/kubernetes/admin.conf ] && echo -n yes || true');
local api_reachable = shellExec('curl -sk https://192.168.56.11:6443/healthz >/dev/null 2>/dev/null && echo -n yes || true');
local my_ip = shellExec("ip -4 addr show | grep -oP '192\\.168\\.56\\.\\d+' | head -1");

// ---------- Phase 1: System preconditions ----------
(if swap_on != '0' then {
   disable_swap: Resource('shell', {
     command: 'swapoff -a && sed -i "/ swap /d" /etc/fstab',
   }),
 } else {}) +

// ---------- Phase 2: Package cache update ----------
(if is_ubuntu then {
  update_cache: Resource('apt_update', {}),
} else {
  update_cache: Resource('dnf_update', {}),
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
  }, deps=['update_cache'] + (if is_centos then ['docker_repo'] else [])),

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
  kubelet: Resource(pkg_type, { name: 'kubelet' }, deps=['containerd_service'] + (if is_ubuntu && k8s_apt_repo_added != 'yes' then ['repo_update'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['repo_update'] else [])),
  kubectl: Resource(pkg_type, { name: 'kubectl' }, deps=['containerd_service'] + (if is_ubuntu && k8s_apt_repo_added != 'yes' then ['repo_update'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['repo_update'] else [])),
  kubeadm: Resource(pkg_type, { name: 'kubeadm' }, deps=['containerd_service'] + (if is_ubuntu && k8s_apt_repo_added != 'yes' then ['repo_update'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['repo_update'] else [])),
  cni_plugins: Resource(pkg_type, { name: 'kubernetes-cni' }, deps=['containerd_service'] + (if is_ubuntu && k8s_apt_repo_added != 'yes' then ['repo_update'] else if is_centos && k8s_rpm_repo_added != 'yes' then ['repo_update'] else [])),
} +

// ---------- Phase 6: Cluster init or join ----------
(if already_init == 'yes' then {
  setup_kubectl: Resource('shell', {
    command: 'mkdir -p $HOME/.kube && [ -f /etc/kubernetes/admin.conf ] && cp /etc/kubernetes/admin.conf $HOME/.kube/config 2>/dev/null; true',
  }),
  cni_install: Resource('shell', {
    command: 'kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml 2>/dev/null; true',
  }, deps=['setup_kubectl']),
} else if api_reachable != 'yes' then {
  cluster_init: Resource('shell', {
    command: 'kubeadm init --apiserver-advertise-address=' + my_ip + ' --control-plane-endpoint=192.168.56.11:6443 --pod-network-cidr=10.244.0.0/16',
    output_name: 'init_output',
  }, deps=['kubeadm', 'containerd', 'cni_plugins']),

  gen_cert_key: Resource('shell', {
    command: 'openssl rand -hex 32',
    output_name: 'cert_key',
    kv_export: { key: 'k8s_cert_key' },
  }),

  upload_certs: Resource('shell', {
    command: 'kubeadm init phase upload-certs --upload-certs --certificate-key {{ ctx.gen_cert_key }} 2>/dev/null; true',
    deps: ['cluster_init', 'gen_cert_key'],
  }),

  token_extract: Resource('shell', {
    command: 'kubeadm token create --ttl 0 2>/dev/null',
    output_name: 'k8s_token',
    kv_export: { key: 'k8s_token' },
    deps: ['setup_kubectl'],
  }),

  hash_extract: Resource('shell', {
    command: 'openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed "s/^.* //"',
    output_name: 'k8s_hash',
    kv_export: { key: 'k8s_hash' },
    deps: ['cluster_init'],
  }),

  setup_kubectl: Resource('shell', {
    command: 'mkdir -p $HOME/.kube && cp /etc/kubernetes/admin.conf $HOME/.kube/config 2>/dev/null; true',
  }, deps=['cluster_init']),
  patch_apiserver: Resource('shell', {
    command: |||
      grep -q "bind-address=0.0.0.0" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || sed -i "/- --advertise-address/a\\    - --bind-address=0.0.0.0" /etc/kubernetes/manifests/kube-apiserver.yaml
      touch /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null; true
    |||,
  }, deps=['setup_kubectl']),
  cni_install: Resource('shell', {
    command: 'kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml 2>/dev/null; true',
  }, deps=['patch_apiserver']),
} else {
  cluster_join: Resource('shell', {
    command: std.strReplace(|||
      kubeadm join 192.168.56.11:6443 --token {{ ctx.global.k8s_token }} --discovery-token-ca-cert-hash sha256:{{ ctx.global.k8s_hash }} --control-plane --certificate-key {{ ctx.global.k8s_cert_key }} --apiserver-advertise-address={{my_ip}} --ignore-preflight-errors=all
    |||, '{{my_ip}}', my_ip),
  }, deps=['kubeadm', 'containerd', 'cni_plugins']),
  setup_kubectl: Resource('shell', {
    command: 'mkdir -p $HOME/.kube && [ -f /etc/kubernetes/admin.conf ] && cp /etc/kubernetes/admin.conf $HOME/.kube/config 2>/dev/null; true',
  }, deps=['cluster_join']),
  patch_apiserver: Resource('shell', {
    command: |||
      grep -q "bind-address=0.0.0.0" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || sed -i "/- --advertise-address/a\\    - --bind-address=0.0.0.0" /etc/kubernetes/manifests/kube-apiserver.yaml
      touch /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null; true
    |||,
  }, deps=['setup_kubectl']),
})