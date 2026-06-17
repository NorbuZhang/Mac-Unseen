// SPDX-License-Identifier: MPL-2.0

enum ComputerMottos {
    private static let curated = """
    世界上有 10 种人：懂二进制的，和不懂的
    计算机很快，等待它的人不一定
    先别重启，让我看看日志
    能跑不等于能解释
    缓存是一种礼貌，也是一种误会
    每个进度条都懂一点心理学
    递归：参见“递归”
    代码不会撒谎，但注释偶尔会
    没有永远的 Bug，只有暂时没触发
    99 个小问题，修复后还有 117 个
    编译通过，是故事的序章
    真正的云，只是别人的电脑
    Ctrl + Z 是数字世界的后悔药
    程序员最短的恐怖故事：线上可复现
    软件的重量，通常由依赖决定
    一切正常，直到时区加入讨论
    日期时间是披着数字外衣的哲学
    测试环境从不代表周五下午
    先测量，再优化
    内存足够，只是暂时还没用完
    风扇转起来，说明芯片在认真思考
    0 和 1 之间，住着整个互联网
    第一只计算机鼠标是木头做的
    QWERTY 键盘比现代计算机更古老
    互联网和万维网不是同一个东西
    一个字节通常有 8 个比特
    ASCII 最初只需要 7 个比特
    Unicode 的目标，是让文字少迷路
    Unix 时间从 1970 年开始计数
    闰秒提醒计算机：地球并不守时
    图灵机很抽象，影响却很具体
    冯·诺依曼架构让程序和数据住在一起
    第一段程序，往往先输出一句问候
    “Hello, World!” 出生于 20 世纪 70 年代
    摩尔定律是观察，不是自然定律
    SSD 没有机械磁头，但也需要休息
    RAM 断电后通常会忘记一切
    CPU 的时钟很快，时间观念却很简单
    GPU 擅长同时做许多相似的事
    编译器是最严格的文字编辑
    链接器专门处理“我明明写了它”
    DNS 是互联网的通讯录
    IP 地址告诉数据往哪里走
    localhost 是计算机写给自己的信
    端口不是插孔，是软件门牌号
    Ping 测的是往返，不是单程
    延迟低，不代表带宽一定高
    压缩是在用计算换空间
    加密不是隐藏算法，而是保护密钥
    哈希更像指纹，不是保险箱
    随机数有时需要非常认真地制造
    熵越珍贵，密码学越安心
    开源不等于没人负责
    版本号是一种克制的叙事
    Git 保存的是快照，不只是差异
    分支很轻，合并需要沟通
    提交信息是写给未来自己的便签
    README 是项目的第一块显示屏
    API 是软件之间约定好的礼貌
    JSON 很轻，逗号很重
    YAML 看起来轻松，空格却很认真
    正则表达式：先解决一个问题，再获得两个
    数据库索引像书的目录，也会占位置
    事务负责让“要么全部，要么没有”
    备份未经恢复测试，只是一种愿望
    RAID 不是备份，重复三遍也不是
    容器不是虚拟机，只是看起来很独立
    沙盒的边界，比名字听起来更认真
    权限越少，意外越少
    最安全的默认值通常是拒绝
    传感器负责测量，软件负责误解
    精度和准确度不是同一件事
    采样率越高，数据不一定越有意义
    噪声不是错误，它也是测量的一部分
    平滑曲线会让世界显得更镇定
    平均值很平静，峰值记得所有瞬间
    温度是芯片写给散热系统的消息
    功耗是性能留下的脚印
    电池百分比是一种经过计算的估计
    屏幕角度里也藏着一枚传感器
    """.split(separator: "\n").map(String.init)

    private static let scenes = """
    当编译器突然沉默
    当进度条停在 99%
    当风扇开始加速
    当日志只写了一句正常
    当测试全部变绿
    当缓存刚被清空
    当网络延迟忽然归零
    当代码第一次运行
    当需求只改一个小地方
    当你决定不写注释
    当传感器读数过于完美
    当周五准备发布
    """.split(separator: "\n").map(String.init)

    private static let endings = """
    计算机通常已经知道下一幕
    先深呼吸，再打开控制台
    真相可能正在另一个线程里
    这往往只是故事的开始
    最好顺手检查一下边界条件
    时间和时区正在赶来的路上
    不妨问问是不是缓存的功劳
    未来的你会感谢一条清楚的日志
    先保存现场，再讨论玄学
    可靠的答案通常来自再次测量
    """.split(separator: "\n").map(String.init)

    private static let all = curated + scenes.flatMap { scene in
        endings.map { "\(scene)，\($0)" }
    }

    private static let englishCurated = """
    There are 10 kinds of people. You know the rest.
    It works on my machine. The machine has declined to comment.
    First rule of debugging: reproduce the confidence.
    The cloud is someone else's computer with excellent branding.
    A cache is a tiny museum of yesterday's truth.
    DNS: because remembering numbers was apparently too reliable.
    The progress bar is mostly emotional support.
    Recursion: see recursion.
    The compiler has reviewed your work and has notes.
    Production is where edge cases become main characters.
    There is no place like 127.0.0.1.
    Git remembers everything except why you did it.
    A clean build is not a personality.
    The bug cannot reproduce under direct observation.
    Friday deploys build character, mostly for on-call engineers.
    The fastest code is the code nobody runs.
    Two hard problems: cache invalidation, naming, and off-by-one errors.
    Backups are optimism until someone tests restore.
    Latency is just distance wearing a stopwatch.
    Every abstraction eventually sends an invoice.
    The fan is the laptop's way of clearing its throat.
    RAM is where unfinished thoughts go to feel important.
    The keyboard knows how often you changed your mind.
    A byte is eight bits of collective agreement.
    Unix time has been counting since 1970 and still has no weekend.
    Unicode is proof that text is infrastructure.
    The first computer mouse was made of wood.
    QWERTY predates every app currently open.
    An API is a promise with version numbers.
    JSON is simple until one comma gains authority.
    YAML believes whitespace should have consequences.
    Regex is a compact way to own two problems.
    Encryption protects secrets. Hashing gives them fingerprints.
    Randomness takes a surprising amount of planning.
    The database is fast because the index did the reading first.
    Containers are processes with excellent boundaries.
    Least privilege: trust, but with a very short guest list.
    Sensors measure reality. Software negotiates with it.
    Precision and accuracy are cousins, not twins.
    Measure first. Make the chart pretty second.
    """.split(separator: "\n").map(String.init)

    private static let englishScenes = """
    When the compiler suddenly goes quiet
    When the progress bar reaches 99%
    When the fans begin their keynote
    When the log says everything is fine
    When every test turns green
    When the cache has just been cleared
    When latency drops to zero
    When the code works on the first run
    When the request is only a tiny change
    When someone says comments are unnecessary
    When the sensor data looks too perfect
    When deployment is scheduled for Friday
    When the demo starts in five minutes
    When production cannot reproduce staging
    When the branch is named final-final
    When the fix is one line long
    """.split(separator: "\n").map(String.init)

    private static let englishEndings = """
    the computer already knows where this is going.
    open the console before opening your heart.
    the truth is probably running on another thread.
    that is usually where the plot begins.
    check the boundary conditions and your assumptions.
    time zones are already on their way.
    ask whether the cache deserves the credit.
    future you would appreciate a useful log line.
    preserve the evidence before invoking magic.
    measure it one more time.
    """.split(separator: "\n").map(String.init)

    private static let englishAll = englishCurated + englishScenes.flatMap { scene in
        englishEndings.map { "\(scene), \($0)" }
    }

    static var count: Int {
        min(all.count, englishAll.count)
    }

    static func randomIndex() -> Int {
        Int.random(in: 0..<max(count, 1))
    }

    static func motto(at index: Int, language: AppLanguage) -> String {
        let source = language == .english ? englishAll : all
        guard !source.isEmpty else {
            return language == .english ? "Measure first." : "先测量，再优化"
        }
        return source[index % source.count]
    }
}
