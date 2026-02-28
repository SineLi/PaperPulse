import 'package:flutter/material.dart';

void showPolicyDialog(
  BuildContext context, {
  required String title,
  required String content,
}) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: double.maxFinite,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 24, right: 16),
              child: _PolicyContentFormatter(content: content),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      );
    },
  );
}

class _PolicyContentFormatter extends StatelessWidget {
  final String content;

  const _PolicyContentFormatter({required this.content});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final lines = content.split('\n');
    final List<Widget> widgets = [];

    for (var line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      final trimmed = line.trim();

      // 一级标题："一、" 或 "1."
      if (RegExp(r'^([一二三四五六七八九十]、|\d+\.)\s*').hasMatch(trimmed)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Text(
              trimmed,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        );
      }
      // 二级标题："2.1" 或 "2.2"
      else if (RegExp(r'^\d+\.\d+\s*').hasMatch(trimmed)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
            child: Text(
              trimmed,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        );
      }
      // 更新日期
      else if (trimmed.startsWith('更新日期')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Text(
              trimmed,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
        );
      }
      // 普通正文
      else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(
              trimmed,
              style: textTheme.bodyMedium?.copyWith(
                height: 1.6, // 增加行高，提升阅读体验
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

// 示例内容
const String userAgreementContent = '''
更新日期：2026-02-28

一、接受条款
欢迎使用 PaperPulse（以下简称“本服务”或“我们”）。使用本服务前，请仔细阅读并理解本协议的全部条款。你通过安装、访问或以其它方式使用本服务即表示已同意并受本协议约束。如果你不同意本协议的任何内容，请不要注册或使用本服务。

二、名词定义
“用户”或“你”：指使用本服务的个人或机构。
“账户”：用户通过注册获得的标识（用户名、邮箱及登录凭证）。
“内容”：指通过本服务提供或生成的信息，包括但不限于文章条目、摘要、LLM 生成的文本、图形摘要等。

三、服务内容
PaperPulse 为科研文献聚合与管理工具，主要功能包括：订阅期刊、接收文章推送、保存/收藏/标记阅读状态、展示文章的图形摘要及 LLM 自动生成的解读/摘要等。LLM 相关的处理在后端完成并将生成结果回传到客户端用于展示。

四、账户与认证
注册与登录：用户需提供用户名、邮箱与密码以注册账户。
令牌存储：客户端将访问令牌存储在平台安全存储中。
你有义务妥善保管你的账户信息与登录凭证。若发现账户被未授权使用，应立即通知我们并采取措施（如更改密码、退出登录等）。

五、用户行为与义务
你承诺遵守适用法律，遵守本服务规则，不得利用本服务从事违法或侵权活动。
不得通过本服务发布或传播侵权、诽谤、恶意代码或其他违法违规内容。
对于你上传或提交的内容（如反馈、笔记等），你应保证拥有相应权利并同意我们为提供服务而使用该等内容。

六、LLM 与自动生成内容的声明
本服务使用后端 LLM（大语言模型）对文章摘要进行解析、生成中文标题、摘要、要点等以供展示，LLM 服务在后端被触发并调用第三方 LLM 提供方（如 阿里云）进行生成处理。请注意 LLM 输出可能包含不准确或需要人工核验的描述，我们不对 LLM 生成内容的绝对正确性承担保证责任。
若你对 LLM 生成内容的隐私与处理有特别要求，请在使用前阅读本协议的隐私条款或联系支持。

七、知识产权
用户对自己上传或创建的内容保留所有权利，但同意授予我们为提供、展示及改进服务所必需的许可（非独占、可撤销），包括在服务内显示、备份与用于生成个性化体验。

八、免责声明与责任限制
对于因互联网传输故障、第三方服务（包括 LLM 提供方）中断、网络入侵、不可抗力等导致的服务中断、数据丢失或信息延迟，我们在法律允许的范围内不承担责任。
对于 LLM 自动生成的内容、第三方来源的文章内容或外部链接的准确性、合法性、完整性不作保证；用户在引用或基于这些内容做出决策时，应自行核验。
在任何情况下，我们基于本服务造成的可责赔偿责任总额不超过用户因使用本服务而实际支付给我们的服务费用（如有），但不适用于因故意或重大过失导致的法律责任（具体以适用法律为准）。

九、终止与修改
我们有权在必要时修改、暂停或终止全部或部分服务；在法律允许范围内，对服务重大变更或终止会通过应用内或其他适当方式公告。
我们可根据本协议及适用法律对违规用户采取限制、暂停或注销账户等措施。

十、其他
本协议未尽事宜，请参见我们的《隐私政策》。
''';

const String privacyPolicyContent = '''
更新日期：2026-02-28

1. 概述
我们重视用户个人信息与隐私保护。本隐私政策说明我们如何收集、使用、存储、共享与保护你的信息，以及你可行使的权利。使用 PaperPulse 前，请先阅读并理解本隐私政策。若你不同意本隐私政策，请不要使用本服务。

2. 我们收集的信息类别
我们在你使用服务的不同环节会收集以下类型的信息：

  2.1 注册与账户信息（必需）
  用户名、电子邮箱、密码。

  2.2 用户偏好与应用数据

  你订阅/关注的期刊、收藏的文章、已读记录、偏好设置等；这些数据用于个性化服务展示，并存储于后端数据库与客户端本地数据库中。后端用户服务管理这些记录，例如关注期刊、收藏文章等。

  2.3 文章与 LLM 相关内容
  本服务会获取并展示文章的标题、摘要、作者、doi、发表日期、图形摘要链接等元数据。后端会将文章摘要或相关文本发送至后端 LLM 服务以生成中文解读，并把该生成内容存入后端数据库，客户端从后端获取并展示。由此，文章的摘要或片段会被传递给第三方 LLM 提供方进行处理。

  2.4 设备与日志信息
  我们可能收集客户端运行时的基本设备信息（系统、版本）和服务日志（用于故障排查、性能监控及安全审计）。

3. 我们如何使用这些信息
我们可能将上述信息用于下列目的：

提供并维护服务功能（注册、登录、文章推送、收藏、阅读记录、生成并展示 LLM 摘要等）。
改进产品和用户体验（根据用户阅读行为与偏好优化推荐）。
安全与合规（防止滥用、调查违规行为、维护服务可用性）。
技术运维（日志与故障排查、性能优化）。

在你明确同意的情形下，用于通知服务变更、营销或活动信息（你可随时退订）。

4. 关于 LLM（第三方模型）处理

第三方处理说明：为生成文章解读与摘要，我们在后端调用第三方 LLM 服务。也就是说，文章摘要或文本片段会被发送至第三方进行处理并返回生成结果。请注意第三方服务对用户数据的使用将受其隐私政策约束。

风险提示：第三方 LLM 的处理可能导致生成内容不可预见或包含不完全准确的信息；此外，第三方可能会有自己的日志或保留策略。

5. 数据共享与第三方

我们不会未经允许向无关联第三方出售你的个人信息。
我们会在下列情形与第三方分享你的信息：
为提供服务而必须的第三方（例如 LLM 提供方、托管/运维服务商）。
法律法规要求或司法机关、监管机关依法要求时。
经过你明确同意的分享。

对于第三方服务（尤其 LLM）如何处理数据，你应参阅这些第三方的隐私政策并理解相应风险。

6. 儿童隐私

本服务不面向儿童（通常定义为未满 14 岁或你所在司法辖区认定的未成年人）。

7. 隐私政策的更新

我们可能会不时更新本隐私政策。对于重大变更，我们会在应用内或通过登记邮箱向用户告知。继续使用服务即表示你接受更新后的政策。
''';
