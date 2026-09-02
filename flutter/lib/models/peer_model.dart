import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'platform_model.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

class Peer {
  final String id;
  String hash; // personal ab hash password
  String password; // shared ab password
  String username; // pc username
  String hostname;
  String platform;
  String alias;
  List<dynamic> tags;
  bool forceAlwaysRelay = false;
  String rdpPort;
  String rdpUsername;
  bool online = false;
  String loginName; //login username
  String device_group_name;
  String note;
  bool? sameServer;

  String getId() {
    if (alias != '') {
      return alias;
    }
    return id;
  }

  Peer.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? '',
        hash = json['hash'] ?? '',
        password = json['password'] ?? '',
        username = json['username'] ?? '',
        hostname = json['hostname'] ?? '',
        platform = json['platform'] ?? '',
        alias = json['alias'] ?? '',
        tags = json['tags'] ?? [],
        forceAlwaysRelay = json['forceAlwaysRelay'] == 'true',
        rdpPort = json['rdpPort'] ?? '',
        rdpUsername = json['rdpUsername'] ?? '',
        loginName = json['loginName'] ?? '',
        device_group_name = json['device_group_name'] ?? '',
        note = json['note'] is String ? json['note'] : '',
        sameServer = json['same_server'];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "hash": hash,
      "password": password,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "alias": alias,
      "tags": tags,
      "forceAlwaysRelay": forceAlwaysRelay.toString(),
      "rdpPort": rdpPort,
      "rdpUsername": rdpUsername,
      'loginName': loginName,
      'device_group_name': device_group_name,
      'note': note,
      'same_server': sameServer,
    };
  }

  Map<String, dynamic> toCustomJson({required bool includingHash}) {
    var res = <String, dynamic>{
      "id": id,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "alias": alias,
      "tags": tags,
    };
    if (includingHash) {
      res['hash'] = hash;
    }
    return res;
  }

  Map<String, dynamic> toGroupCacheJson() {
    return <String, dynamic>{
      "id": id,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "login_name": loginName,
      "device_group_name": device_group_name,
    };
  }

  Peer({
    required this.id,
    required this.hash,
    required this.password,
    required this.username,
    required this.hostname,
    required this.platform,
    required this.alias,
    required this.tags,
    required this.forceAlwaysRelay,
    required this.rdpPort,
    required this.rdpUsername,
    required this.loginName,
    required this.device_group_name,
    required this.note,
    this.sameServer,
  });

  Peer.loading()
      : this(
          id: '...',
          hash: '',
          password: '',
          username: '...',
          hostname: '...',
          platform: '...',
          alias: '',
          tags: [],
          forceAlwaysRelay: false,
          rdpPort: '',
          rdpUsername: '',
          loginName: '',
          device_group_name: '',
          note: '',
        );
  bool equal(Peer other) {
    return id == other.id &&
        hash == other.hash &&
        password == other.password &&
        username == other.username &&
        hostname == other.hostname &&
        platform == other.platform &&
        alias == other.alias &&
        tags.equals(other.tags) &&
        forceAlwaysRelay == other.forceAlwaysRelay &&
        rdpPort == other.rdpPort &&
        rdpUsername == other.rdpUsername &&
        device_group_name == other.device_group_name &&
        loginName == other.loginName &&
        note == other.note;
  }

  Peer.copy(Peer other)
      : this(
            id: other.id,
            hash: other.hash,
            password: other.password,
            username: other.username,
            hostname: other.hostname,
            platform: other.platform,
            alias: other.alias,
            tags: other.tags.toList(),
            forceAlwaysRelay: other.forceAlwaysRelay,
            rdpPort: other.rdpPort,
            rdpUsername: other.rdpUsername,
            loginName: other.loginName,
            device_group_name: other.device_group_name,
            note: other.note,
            sameServer: other.sameServer);
}

enum UpdateEvent { online, load }

typedef GetInitPeers = RxList<Peer> Function();

/// 进程级“在线权威表” + 活跃列表实例注册表。
///
/// 背景：最近/收藏/局域网/通讯录/群组每个列表各有一个 Peers 实例，顶部输入框
/// 的自动补全(AllPeersLoader)又会把各列表的 Peer 重新打包成新对象。此前每个
/// 实例各自维护一份 _onlineStates，而 AllPeersLoader 重建对象时 online 恒为
/// false，导致“服务器确认在线、但手机端任意列表/补全里始终灰点”。
///
/// 因此把权威表提升为 static，全进程共享：
///  - 任何一个 Peers 实例收到服务端推送(online/offline)都写入同一张表；
///  - 任何列表 load、任何地方重建 Peer，都能用 Peers.onlineOf(id) 回填；
///  - 任一实例查询到新状态后，所有活跃实例同步本地 peers.online 并通知 UI。
class Peers extends ChangeNotifier {
  /// 进程级权威表：id -> online。全实例共享、跨实例存活。
  static final Map<String, bool> _onlineStates = {};

  /// 当前存活的 Peers 实例（供状态广播）。
  static final List<Peers> _instances = [];

  /// 供外部(如 AllPeersLoader)查询某 id 的真实在线状态；未知返回 null。
  static bool? onlineOf(String id) {
    if (id.isEmpty) return null;
    return _onlineStates[id];
  }

  /// 供外部把权威表回填到一组重建后的 Peer 对象上。
  static void restoreOnline(Iterable<Peer> peers) {
    for (final peer in peers) {
      if (peer.id.isNotEmpty && _onlineStates.containsKey(peer.id)) {
        peer.online = _onlineStates[peer.id] ?? false;
      }
    }
  }

  static void _broadcast(Peers? source) {
    for (final inst in _instances) {
      if (identical(inst, source)) continue;
      inst._syncFromShared();
    }
  }

  final String name;
  final String loadEvent;
  List<Peer> peers = List.empty(growable: true);
  // Part of the peers that are not in the rest peers list.
  // When there're too many peers, we may want to load the front 100 peers first,
  // so we can see peers in UI quickly. `restPeerIds` is the rest peers' ids.
  // And then load all peers later.
  List<String> restPeerIds = List.empty(growable: true);
  final GetInitPeers? getInitPeers;
  UpdateEvent event = UpdateEvent.load;
  static const _cbQueryOnlines = 'callback_query_onlines';

  Peers(
      {required this.name,
      required this.getInitPeers,
      required this.loadEvent}) {
    _instances.add(this);
    peers = getInitPeers?.call() ?? [];
    // 创建即用进程级共享表回填一次，保证后创建的列表(如切到通讯录 tab 才
    // 懒加载的实例)直接显示正确状态，而不是先全灰再等查询。
    Peers.restoreOnline(peers);
    platformFFI.registerEventHandler(_cbQueryOnlines, name, (evt) async {
      _updateOnlineState(evt);
    });
    platformFFI.registerEventHandler(loadEvent, name, (evt) async {
      _updatePeers(evt);
    });
  }

  @override
  void dispose() {
    _instances.remove(this);
    platformFFI.unregisterEventHandler(_cbQueryOnlines, name);
    platformFFI.unregisterEventHandler(loadEvent, name);
    super.dispose();
  }

  /// 共享表有变化且不是本实例发起时，把变化同步到本实例并通知 UI。
  void _syncFromShared() {
    var changed = false;
    for (final peer in peers) {
      if (peer.id.isNotEmpty &&
          _onlineStates.containsKey(peer.id) &&
          peer.online != _onlineStates[peer.id]) {
        peer.online = _onlineStates[peer.id] ?? false;
        changed = true;
      }
    }
    if (changed) {
      event = UpdateEvent.online;
      notifyListeners();
    }
  }

  Peer getByIndex(int index) {
    if (index < peers.length) {
      return peers[index];
    } else {
      return Peer.loading();
    }
  }

  int getPeersCount() {
    return peers.length;
  }

  void _updateOnlineState(Map<String, dynamic> evt) {
    int changedCount = 0;

    void apply(String id, bool online) {
      if (id.isEmpty) return;
      // 权威表先行：即使该 id 此刻不在当前列表中（例如另一个列表/刚刚切换
      // 加载），也记录下来，等它下一次被 load 进来时直接回填成正确状态。
      final existed = _onlineStates.containsKey(id);
      if (!existed || _onlineStates[id] != online) {
        _onlineStates[id] = online;
        changedCount += 1;
      }
      for (var i = 0; i < peers.length; i++) {
        if (peers[i].id == id && peers[i].online != online) {
          peers[i].online = online;
        }
      }
    }

    final onlines = (evt['onlines'] as String? ?? '').trim();
    final offlines = (evt['offlines'] as String? ?? '').trim();
    if (onlines.isNotEmpty) {
      onlines.split(',').forEach((id) => apply(id.trim(), true));
    }
    if (offlines.isNotEmpty) {
      offlines.split(',').forEach((id) => apply(id.trim(), false));
    }

    if (changedCount > 0) {
      event = UpdateEvent.online;
      notifyListeners();
      // 通知其它列表实例：它们列表里若有同 id 的卡片，立即翻绿/翻灰，
      // 而不是等到自己下一次轮询(最长 10~30s)才更新。
      _broadcast(this);
    }
  }

  void _updatePeers(Map<String, dynamic> evt) {
    if (getInitPeers != null) {
      peers = getInitPeers?.call() ?? [];
    } else {
      peers = _decodePeers(evt['peers']);
    }

    restPeerIds = [];
    if (evt['ids'] != null) {
      restPeerIds = (evt['ids'] as String).split(',');
    }

    // 用跨 load 存活的权威表回填：之前已被服务端确认在线的设备，重新加载后
    // 依然显示在线，而不是先被重置成灰、再等异步查询“碰运气”翻绿。
    for (var peer in peers) {
      peer.online = _onlineStates[peer.id] ?? false;
    }

    // 权威表未知的 peer（第一次被 load 进来，服务端在线状态还没有任何缓存）
    // 立即补一次查询，避免这类设备一直灰到下一次 load/轮询才翻绿。查询走
    // Rust 侧无界队列，绝不会因为并发 load 而丢请求。
    final unknown = <String>[
      for (final peer in peers)
        if (!_onlineStates.containsKey(peer.id)) peer.id,
    ];
    if (unknown.isNotEmpty) {
      bind.queryOnlines(ids: unknown);
    }

    event = UpdateEvent.load;
    notifyListeners();
  }

  List<Peer> _decodePeers(String peersStr) {
    try {
      if (peersStr == "") return [];
      List<dynamic> peers = json.decode(peersStr);
      return peers.map((peer) {
        return Peer.fromJson(peer as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('peers(): $e');
    }
    return [];
  }
}
