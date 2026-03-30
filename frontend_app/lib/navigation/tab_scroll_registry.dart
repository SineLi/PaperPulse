import 'package:flutter/material.dart';

const int journalsTabIndex = 0;
const int favoritesTabIndex = 1;
const int feedTabIndex = 2;

class TabScrollRegistry {
  final Map<int, ScrollController> _controllers = {};

  void register(int tabIndex, ScrollController controller) {
    _controllers[tabIndex] = controller;
  }

  void unregister(int tabIndex, ScrollController controller) {
    if (_controllers[tabIndex] == controller) {
      _controllers.remove(tabIndex);
    }
  }

  Future<void> scrollToTop(int tabIndex) async {
    final controller = _controllers[tabIndex];
    if (controller == null || !controller.hasClients) {
      return;
    }

    // The shell triggers the action, but the page still owns the controller.
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}
