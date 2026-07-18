// UPnP (Universal Plug and Play) 端口映射模块
//
// 自动将 direct_server 监听的本地端口映射到路由器 WAN 端，
// 使外网可以直接通过 公网IP:端口 访问本机，无需用户手动配置端口转发。
//
// 使用 igd-next crate 与路由器的 IGD (Internet Gateway Device) 通信。
// ⚠ 需要路由器支持 UPnP（大部分家用路由器默认开启）。

use hbb_common::log::{info, warn};

/// 尝试为指定端口添加 UPnP 端口映射（TCP）。
/// 返回是否成功添加了映射。
pub fn add_port_mapping(port: u16) -> Option<u16> {
    match try_add_mapping(port) {
        Ok(external_port) => {
            info!(
                "UPnP: mapped external TCP:{} to local TCP:{}",
                external_port, port
            );
            Some(external_port)
        }
        Err(e) => {
            warn!("UPnP: failed to map local TCP:{}: {}", port, e);
            None
        }
    }
}

/// 尝试删除指定端口的 UPnP 端口映射。
pub fn remove_port_mapping(port: u16) -> bool {
    match try_remove_mapping(port) {
        Ok(_) => {
            info!("✅ UPnP: 成功删除端口映射 {}", port);
            true
        }
        Err(e) => {
            warn!("UPnP: 删除端口映射 {} 失败: {}", port, e);
            false
        }
    }
}

fn try_add_mapping(port: u16) -> Result<u16, Box<dyn std::error::Error>> {
    let gateway = igd_next::search_gateway(Default::default())?;

    let local_ipv4 = get_local_lan_ip().ok_or("无法获取本机 LAN IP")?;
    let local_addr = std::net::SocketAddr::new(local_ipv4.into(), port);
    if let Some(external_port) = find_existing_mapping(&gateway, local_ipv4, port) {
        info!(
            "UPnP: reusing external TCP:{} mapped to {}:{}",
            external_port, local_ipv4, port
        );
        return Ok(external_port);
    }
    info!(
        "UPnP: 本机 LAN IP {:?}, 映射外部 TCP:{} -> {}:{}",
        local_ipv4, port, local_ipv4, port
    );

    match gateway.add_port(
        igd_next::PortMappingProtocol::TCP,
        port,
        local_addr,
        0,
        "LUODA Remote Desktop",
    ) {
        Ok(()) => Ok(port),
        Err(igd_next::AddPortError::PortInUse) => {
            let external_port = gateway.add_any_port(
                igd_next::PortMappingProtocol::TCP,
                local_addr,
                0,
                "LUODA Remote Desktop",
            )?;
            info!(
                "UPnP: preferred external port {} was occupied; router assigned {}",
                port, external_port
            );
            Ok(external_port)
        }
        Err(e) => Err(Box::new(e)),
    }
}

fn find_existing_mapping(
    gateway: &igd_next::Gateway,
    local_ipv4: std::net::Ipv4Addr,
    local_port: u16,
) -> Option<u16> {
    let local_ip = local_ipv4.to_string();
    for index in 0..256 {
        match gateway.get_generic_port_mapping_entry(index) {
            Ok(entry)
                if entry.enabled
                    && entry.protocol == igd_next::PortMappingProtocol::TCP
                    && entry.internal_port == local_port
                    && entry.internal_client == local_ip =>
            {
                return Some(entry.external_port);
            }
            Ok(_) => {}
            Err(igd_next::GetGenericPortMappingEntryError::SpecifiedArrayIndexInvalid) => {
                break;
            }
            Err(e) => {
                warn!("UPnP: could not enumerate existing mappings: {}", e);
                break;
            }
        }
    }
    None
}

fn get_local_lan_ip() -> Option<std::net::Ipv4Addr> {
    // 优先方案：用 direct_access 模块智能选择内网 IP
    // 枚举所有网卡 + 评分（192.168.x.x >> 10.x.x.x > 172.16-31.x.x），
    // 避开 VPN/WSL/Docker/Hyper-V 等虚拟网卡。UDP connect 法只能拿默认路由
    // 出口 IP，多网卡/VPN 环境下会拿错（例如真实网卡是 192.168.x.x 但默认路由
    // 走的是 10.x.x.x 网卡，UDP connect 法返回的就只能是 10.x.x.x）。
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let ifaces: Vec<default_net::interface::Interface> =
            default_net::interface::get_interfaces();
        let candidates: Vec<crate::direct_access::LanAddressCandidate> = ifaces
            .iter()
            .flat_map(|iface| {
                iface.ipv4.iter().map(move |ipnet| {
                    let name_lower = iface.name.to_lowercase();
                    let virtual_markers = [
                        "virtual", "vethernet", "vmware", "virtualbox",
                        "vbox", "hyper-v", "hyperv", "wsl", "docker",
                        "tailscale", "wireguard", "vpn", "tunnel",
                        "loopback", "bluetooth", "bt", "pseudo",
                        "tun", "tap", "ppp", "pppoe",
                        "isatap", "teredo", "6to4",
                    ];
                    let is_physical = !virtual_markers.iter().any(|m| name_lower.contains(m));
                    crate::direct_access::LanAddressCandidate {
                        address: ipnet.addr,
                        name: iface.name.clone(),
                        is_default: false,
                        has_gateway: iface.gateway.is_some(),
                        is_physical,
                    }
                })
            })
            .collect();

        if let Some(ip) = crate::direct_access::choose_lan_ipv4(&candidates) {
            info!("UPnP: LAN IP detected via direct_access: {}", ip);
            return Some(ip);
        }
    }

    // 兜底方案：UDP connect 8.8.8.8 取默认路由出口 IP
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let addr = socket.local_addr().ok()?;
    match addr.ip() {
        std::net::IpAddr::V4(v4) => Some(v4),
        _ => None,
    }
}

fn try_remove_mapping(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let gateway = igd_next::search_gateway(Default::default())?;
    gateway.remove_port(igd_next::PortMappingProtocol::TCP, port)?;
    Ok(())
}
