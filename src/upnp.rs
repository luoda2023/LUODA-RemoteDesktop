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
pub fn add_port_mapping(port: u16) -> bool {
    match try_add_mapping(port) {
        Ok(_) => {
            info!("✅ UPnP: 成功添加端口映射 {} (TCP) → 本机:{}", port, port);
            true
        }
        Err(e) => {
            warn!("UPnP: 无法添加端口映射 {}: {} (路由器可能不支持或未开启 UPnP)", port, e);
            false
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

fn try_add_mapping(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    // igd-next 的典型用法：搜索网关，添加端口映射
    let gateway = match igd_next::search_gateway(Default::default()) {
        Ok(g) => g,
        Err(e) => {
            return Err(format!("搜索网关失败: {}", e).into());
        }
    };

    // 获取本机的 LAN IP（路由器看到的本机地址），不是 127.0.0.1
    let local_ipv4 = get_local_lan_ip().ok_or("无法获取本机 LAN IP")?;
    let local_addr = std::net::SocketAddr::new(local_ipv4.into(), port);
    info!(
        "UPnP: 本机 LAN IP {:?}, 映射外部 TCP:{} -> {}:{}",
        local_ipv4, port, local_ipv4, port
    );

    gateway.add_port(
        igd_next::PortMappingProtocol::TCP,
        port,
        local_addr,
        0, // lease_duration = 0 表示永久映射
        "LUODA Remote Desktop",
    )?;

    Ok(())
}

/// 获取本机在 LAN 中的 IP（不是 127.0.0.1，不是公网 IP）。
/// 通过创建一个 UDP socket "连"到 8.8.8.8:80 来探测路由器看到的本机地址。
fn get_local_lan_ip() -> Option<std::net::Ipv4Addr> {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let addr = socket.local_addr().ok()?;
    match addr.ip() {
        std::net::IpAddr::V4(v4) => Some(v4),
        _ => None,
    }
}

fn try_remove_mapping(port: u16) -> Result<(), Box<dyn std::error::Error>> {
    let gateway = match igd_next::search_gateway(Default::default()) {
        Ok(g) => g,
        Err(e) => {
            return Err(format!("搜索网关失败: {}", e).into());
        }
    };

    gateway.remove_port(igd_next::PortMappingProtocol::TCP, port)?;
    Ok(())
}
