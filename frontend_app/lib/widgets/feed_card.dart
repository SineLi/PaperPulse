import 'package:flutter/material.dart';

class FeedItemCard extends StatelessWidget {
  const FeedItemCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias, // 关键：让右侧图片也跟着圆角裁剪
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 140,
          child: Row(
            children: [
              // 左侧信息区
              Expanded(
                child: Container(
                  color: const Color(0xFFF6F3FF), // 轻微的淡紫背景，接近示意图
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部：头像 + Journal · 2h
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 14,
                            backgroundColor: Color(0xFF0F8A6A),
                            child: Text(
                              'TC',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              overflow: TextOverflow.ellipsis,
                              text: const TextSpan(
                                style: TextStyle(
                                  color: Color(0xFF2E2E2E),
                                  fontSize: 14,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Journal',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  ·  2h',
                                    style: TextStyle(
                                      color: Color(0xFF7A7A7A),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // 标题
                      const Text(
                        'Title title title',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),

                      const Spacer(),

                      // Tag（示意）
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFEAFB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'tag',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3C2E63),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 右侧 GA 预览区（先用占位）
              SizedBox(
                width: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 占位图：后面你可以换成 Image.network / Image.file
                    Container(
                      color: const Color(0xFFE9E9E9),
                      child: const Center(
                        child: Icon(
                          Icons.image,
                          size: 34,
                          color: Color(0xFF9A9A9A),
                        ),
                      ),
                    ),

                    // 可选：轻微渐变，让图片更像“预览卡片”
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x14000000)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
