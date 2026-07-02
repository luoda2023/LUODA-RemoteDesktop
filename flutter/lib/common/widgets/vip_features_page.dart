import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../consts.dart';

class VipFeaturesPage extends StatefulWidget {
  final EdgeInsets? menuPadding;
  const VipFeaturesPage({Key? key, this.menuPadding}) : super(key: key);

  @override
  State<VipFeaturesPage> createState() => _VipFeaturesPageState();
}

class _VipFeaturesPageState extends State<VipFeaturesPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 64,
            color: Colors.amber.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            translate("VIP features"),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            translate("Coming soon..."),
            style: TextStyle(
              fontSize: 14,
              color: textColor?.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
