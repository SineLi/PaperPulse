import 'package:flutter/material.dart';

const int journalsTabIndex = 0;
const int favoritesTabIndex = 1;
const int feedTabIndex = 2;

class TabScrollRegistry {
  final Map<int, ScrollController> _controllers = {};
  final Map<int, ScrollController> _contentControllers = {};
  final Map<int, Future<bool> Function()> _boundaryScrollers = {};

  void register(int tabIndex, ScrollController controller) {
    _controllers[tabIndex] = controller;
  }

  void unregister(int tabIndex, ScrollController controller) {
    if (_controllers[tabIndex] == controller) {
      _controllers.remove(tabIndex);
    }
  }

  void registerContent(int tabIndex, ScrollController controller) {
    _contentControllers[tabIndex] = controller;
  }

  void unregisterContent(int tabIndex, ScrollController controller) {
    if (_contentControllers[tabIndex] == controller) {
      _contentControllers.remove(tabIndex);
    }
  }

  void registerBoundaryScroller(
    int tabIndex,
    Future<bool> Function() scrollToBoundary,
  ) {
    _boundaryScrollers[tabIndex] = scrollToBoundary;
  }

  void unregisterBoundaryScroller(
    int tabIndex,
    Future<bool> Function() scrollToBoundary,
  ) {
    if (_boundaryScrollers[tabIndex] == scrollToBoundary) {
      _boundaryScrollers.remove(tabIndex);
    }
  }

  bool isAtTop(int tabIndex, {double tolerance = 8}) {
    final controllers =
        <ScrollController?>[
          _controllers[tabIndex],
          _contentControllers[tabIndex],
        ].whereType<ScrollController>().where(
          (controller) => controller.hasClients,
        );
    if (controllers.isEmpty) return false;
    return controllers.every(
      (controller) =>
          controller.offset <= controller.position.minScrollExtent + tolerance,
    );
  }

  /// 首页双击：在顶部时跳到阅读分界，否则保持原有的回顶行为。
  Future<void> handleDoubleTap(int tabIndex) async {
    if (tabIndex == feedTabIndex && isAtTop(tabIndex)) {
      final scrollToBoundary = _boundaryScrollers[tabIndex];
      if (scrollToBoundary != null) {
        await scrollToBoundary();
      }
      // 已在顶部时只处理阅读分界，禁止随后再次触发回顶动画。
      return;
    }
    await scrollToTop(tabIndex);
  }

  /// 先按列表比例无动画预定位，供尚未构建的懒加载锚点进入渲染范围。
  Future<bool> scrollToFraction(int tabIndex, double fraction) async {
    final controller = _contentControllers[tabIndex] ?? _controllers[tabIndex];
    if (controller == null || !controller.hasClients) return false;

    final position = controller.position;
    final extent = position.maxScrollExtent - position.minScrollExtent;
    if (extent <= 0) return false;
    final normalized = fraction.clamp(0.0, 1.0);
    controller.jumpTo(position.minScrollExtent + extent * normalized);
    return true;
  }

  Future<void> scrollToTop(int tabIndex) async {
    final contentController = _contentControllers[tabIndex];
    if (contentController != null && contentController.hasClients) {
      await contentController.animateTo(
        contentController.position.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

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
