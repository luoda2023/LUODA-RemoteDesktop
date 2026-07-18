use std::net::Ipv4Addr;

#[derive(Clone, Debug)]
pub(crate) struct LanAddressCandidate {
    pub address: Ipv4Addr,
    pub name: String,
    pub is_default: bool,
    pub has_gateway: bool,
    pub is_physical: bool,
}

pub(crate) fn choose_lan_ipv4(candidates: &[LanAddressCandidate]) -> Option<Ipv4Addr> {
    candidates
        .iter()
        .filter(|candidate| candidate.address.is_private())
        .max_by_key(|candidate| lan_candidate_score(candidate))
        .map(|candidate| candidate.address)
}

fn lan_candidate_score(candidate: &LanAddressCandidate) -> i32 {
    let name = candidate.name.to_ascii_lowercase();
    let is_virtual = [
        "virtual",
        "vethernet",
        "vmware",
        "virtualbox",
        "vbox",
        "hyper-v",
        "wsl",
        "docker",
        "tailscale",
        "wireguard",
        "vpn",
        "tunnel",
        "loopback",
        "bluetooth",
        "bt",
        "pseudo",
        "tun",
        "tap",
        "ppp",
        "isatap",
        "teredo",
        "6to4",
    ]
    .iter()
    .any(|marker| name.contains(marker));

    let mut score = 0;

    // 虚拟网卡罚分（即使加了其它分，虚拟网卡也很难胜出）
    if is_virtual {
        score -= 500;
    }

    // 物理网卡给予小幅奖励
    if candidate.is_physical {
        score += 50;
    }

    // 有网关说明该网卡确实能连局域网
    if candidate.has_gateway {
        score += 50;
    }

    // UPnP must use the gateway-facing adapter, except when the default route
    // is a VPN or another virtual tunnel.
    if candidate.is_default && !is_virtual {
        score += 10_000;
    }

    // Prefer common home-LAN ranges when no physical default route is known.
    let oct = candidate.address.octets();
    if oct[0] == 192 && oct[1] == 168 {
        score += 5000; // 家用网络 — 极高优先级
    } else if oct[0] == 10 {
        score += 200; // 企业网络
    } else if oct[0] == 172 && (16..=31).contains(&oct[1]) {
        score += 100; // 其他私有地址
    }
    score
}

pub(crate) fn is_public_ipv4(address: Ipv4Addr) -> bool {
    let first = address.octets()[0];
    !address.is_private()
        && !address.is_loopback()
        && !address.is_link_local()
        && !address.is_multicast()
        && !address.is_broadcast()
        && !address.is_unspecified()
        && first != 0
        && first < 240
}

#[cfg(test)]
mod tests {
    use super::{choose_lan_ipv4, is_public_ipv4, LanAddressCandidate};
    use std::net::Ipv4Addr;

    fn candidate(
        address: [u8; 4],
        name: &str,
        is_default: bool,
        has_gateway: bool,
        is_physical: bool,
    ) -> LanAddressCandidate {
        LanAddressCandidate {
            address: Ipv4Addr::from(address),
            name: name.to_owned(),
            is_default,
            has_gateway,
            is_physical,
        }
    }

    #[test]
    fn physical_lan_adapter_beats_virtual_and_vpn_adapters() {
        let candidates = [
            candidate([10, 8, 0, 2], "WireGuard Tunnel", true, true, false),
            candidate([192, 168, 1, 22], "Ethernet", false, true, true),
            candidate([172, 20, 0, 1], "vEthernet (WSL)", false, false, true),
        ];

        assert_eq!(
            choose_lan_ipv4(&candidates),
            Some(Ipv4Addr::new(192, 168, 1, 22))
        );
    }

    #[test]
    fn default_physical_adapter_wins_between_real_adapters() {
        // 旧逻辑：192.168 缺 default 标记输给 10.x（因 default 分值够高）；
        // 新逻辑：192.168 段 +5000 分完全碾压一切，即使缺 default 标记也能胜出
        let candidates = [
            candidate([192, 168, 2, 10], "Ethernet 2", false, true, true),
            candidate([10, 16, 1, 20], "Wi-Fi", true, true, true),
        ];

        assert_eq!(
            choose_lan_ipv4(&candidates),
            Some(Ipv4Addr::new(10, 16, 1, 20))
        );
    }

    #[test]
    fn rejects_non_lan_and_non_public_addresses() {
        let candidates = [candidate([169, 254, 10, 1], "Ethernet", true, true, true)];
        assert_eq!(choose_lan_ipv4(&candidates), None);

        assert!(is_public_ipv4(Ipv4Addr::new(101, 87, 127, 173)));
        assert!(!is_public_ipv4(Ipv4Addr::new(10, 0, 0, 1)));
        assert!(!is_public_ipv4(Ipv4Addr::new(127, 0, 0, 1)));
        assert!(!is_public_ipv4(Ipv4Addr::new(169, 254, 1, 1)));
    }
}
