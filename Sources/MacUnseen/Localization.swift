// SPDX-License-Identifier: MPL-2.0

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

@MainActor
final class LanguageSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            AppLocalization.language = language
        }
    }

    init() {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        let initial: AppLanguage = preferred.hasPrefix("zh")
            ? .simplifiedChinese
            : .english
        language = initial
        AppLocalization.language = initial
    }

    var locale: Locale {
        Locale(identifier: language.rawValue)
    }

    func toggle() {
        language = language == .simplifiedChinese
            ? .english
            : .simplifiedChinese
    }
}

enum AppLocalization {
    nonisolated(unsafe) static var language: AppLanguage = {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }()

    static func text(_ key: String) -> String {
        guard language == .english else {
            return key
        }
        if key.hasPrefix("无法启动授权流程：") {
            return key.replacingOccurrences(
                of: "无法启动授权流程：",
                with: "Unable to start the authorization flow: "
            )
        }
        if key.hasPrefix("USB-C / 雷雳接口 ") {
            return key.replacingOccurrences(
                of: "USB-C / 雷雳接口",
                with: "USB-C / Thunderbolt Port"
            )
        }
        if key.hasPrefix("USB 接口 ") {
            return key.replacingOccurrences(
                of: "USB 接口",
                with: "USB Port"
            )
        }
        return EnglishCopy.values[key] ?? key
    }
}

func tr(_ key: String) -> String {
    AppLocalization.text(key)
}

private enum EnglishCopy {
    static let values: [String: String] = [
        "总览": "Overview",
        "运动与震动": "Motion & Vibration",
        "屏幕角度与环境光": "Display Angle & Ambient Light",
        "触控板": "Trackpad",
        "温度": "Temperatures",
        "风扇": "Fans",
        "电池与电源": "Battery & Power",
        "存储": "Storage",
        "网络与接口": "Network & Ports",
        "说明": "About",
        "关于": "About",
        "关于 Mac Unseen": "About Mac Unseen",
        "切换界面语言": "Switch interface language",
        "停止高级传感器": "Stop Hidden Sensors",
        "硬件遥测中心": "Hardware telemetry, minus the boring bits",
        "高级传感器": "Hidden Sensors",
        "需要管理员授权": "Administrator access required",
        "需要启用高级传感器": "Hidden sensors are off",
        "加速度计、陀螺仪、屏幕角度和部分 SMC 数据没有公开接口。应用会通过 macOS 管理员授权启动只读采集进程，不修改风扇、功耗或系统设置。":
            "macOS does not expose public APIs for the accelerometer, gyroscope, display angle, or some SMC data. The app uses administrator approval to launch a read-only collector. It never changes fan control, power settings, or system configuration.",
        "启用并授权": "Enable with Administrator Access",
        "等待系统授权…": "Waiting for macOS approval…",
        "正在连接传感器…": "Connecting sensors…",
        "传感器连接超时，请重试。": "Sensor connection timed out. Please try again.",
        "启用隐藏传感器 🤫": "Enable Hidden Sensors 🤫",
        "向 macOS 请求管理员权限，只读访问屏幕角度、运动、温度、风扇和功耗数据":
            "Ask macOS for administrator approval to read display angle, motion, temperature, fan, and power telemetry.",

        "隐藏彩蛋 · 104°": "HIDDEN FIND · 104°",
        "你找到了展示桌上的秘密": "You found the showroom secret",
        "104°，一台 Mac 最像在等你伸手碰它的角度。":
            "104°: the angle that makes a Mac look like it is waiting for you to fix it.",
        "路过不算，得真正停下来。毕竟你已经很熟悉那种只经过她的心，却没能被留下的感觉了。":
            "Passing through does not count. Stay a while. You have done enough drive-bys in someone else's love story.",
        "背后的故事": "The Story Behind It",
        "关闭": "Close",
        "完成": "Done",
        "104° 背后的故事": "The Story Behind 104°",
        "先认识这个角度": "Meet 104°",
        "104° 常被 Mac 爱好者称作 Apple Store 式的展示角度：屏幕足够打开，让画面和机身轮廓都能被看见；又稍微保留一点克制，好像它正在安静地等你伸手。":
            "Mac fans often call 104° the Apple Store pose: open enough to show off the display and silhouette, but restrained enough to look as though it is quietly waiting for a hand.",
        "为什么偏偏摆在这里？": "Why leave it there?",
        "一种流传很广的零售设计解释是：104° 看起来端正，却未必正好适合每个人的身高和站姿。顾客为了看得更舒服，往往会忍不住伸手调整屏幕。这个小动作会把“站在旁边看看”变成“我正在使用它”，接下来摸摸键盘、滑动触控板、打开几个页面，也就顺理成章了。至少你调整它时，它真的会回应你。":
            "The popular retail-design theory is that 104° looks deliberate without being comfortable for everyone. You adjust the screen, and suddenly you are no longer browsing; you are using the Mac. The keyboard, trackpad, and a few apps usually follow. Best of all, when you make a move, this one actually responds.",
        "那半秒钟可能做了什么": "What that half-second changes",
        "这类说法常用“触摸效应”和“微承诺”来解释：一旦亲手调整设备，人会更容易继续探索，也可能产生一点“它正在按我的方式工作”的心理归属感。和单相思不同，这一次不是你独自在脑海里完成全部交互：Mac 至少真的动了。":
            "Retail psychology calls it touch ownership or a micro-commitment: once you adjust something, you are more likely to keep exploring and start imagining it as yours. Unlike a crush, this interaction is not happening entirely in your head. The Mac did move.",
        "传闻，不是官方定理": "Good lore, not official doctrine",
        "Apple 并没有公开把 104° 写成全球门店统一规范，也没有正式确认上述心理设计目的。门店、机型、桌高和陈列方式都可能不同。所以请把它当作一则很有 Apple 气质、也很值得玩味的零售设计传闻。":
            "Apple has not published 104° as a worldwide store standard or confirmed the psychology behind it. Stores, models, table heights, and displays vary. Treat this as excellent retail folklore with suspiciously good product-design energy.",
        "彩蛋要求屏幕连续停在 104° 约 2 秒。短暂经过不会触发，就像你在她心里仅仅路过，也不会自动拥有故事的后续。":
            "The display must settle at 104° for about two seconds. A brief pass will not trigger it. Cameos rarely get a sequel.",

        "Mac Unseen 0.1": "Mac Unseen 0.1",
        "普通系统遥测与隐藏硬件传感器的统一仪表盘":
            "System telemetry and the Mac sensors you were never meant to see",
        "内存": "Memory",
        "磁盘": "Disk",
        "系统负载": "System Load",
        "1 / 5 / 15 分钟": "1 / 5 / 15 minutes",
        "处理器核心": "CPU Cores",
        "热状态": "Thermal State",
        "运行时间": "Uptime",
        "实时功耗": "Live Power",
        "此机型没有返回可访问的功耗传感器":
            "This Mac does not expose readable power telemetry.",
        "检测到功耗传感器，但当前无法读取":
            "Power sensors were detected, but their readings are unavailable.",
        "这里显示 Mac 当前各部分消耗或传输的电功率，单位是瓦（W）。数值越高，通常表示芯片负载、屏幕亮度、充电活动或外设供电越多。它是即时读数，会随着使用状态快速变化。":
            "Live electrical power used or transferred by different parts of the Mac, measured in watts. Higher readings usually reflect heavier chip load, display brightness, charging, or power delivered to peripherals.",
        "隐藏传感器": "Hidden Sensors",
        "加速度计 + 陀螺仪": "Accelerometer + gyroscope",
        "屏幕铰链角度": "Display hinge angle",
        "照度 + 四路光谱": "Illuminance + four spectral channels",
        "独立温度传感器": "Dedicated temperature sensor",
        "当前状态": "Current Status",
        "高级采集": "Hidden sensor collector",
        "实时运行": "Live",
        "尚未启用": "Not enabled",
        "触控板原始数据": "Raw Trackpad Data",
        "不可用": "Unavailable",
        "电池内部数据": "Battery internals",
        "无需管理员权限": "No administrator access needed",
        "基础系统数据": "Basic system data",

        "读取机身内部 BMI286 IMU，采样频率可在 25–200 Hz 间调整":
            "Live BMI286 motion data with an adjustable 25–200 Hz sample rate",
        "三轴加速度": "3-Axis Acceleration",
        "三轴角速度": "3-Axis Angular Velocity",
        "机身姿态估算": "Estimated Orientation",
        "横滚 Roll": "Roll",
        "俯仰 Pitch": "Pitch",
        "相对偏航 Yaw": "Relative Yaw",
        "机身震动": "Chassis Vibration",
        "动态加速度趋势": "Dynamic acceleration",
        "目标采样频率": "Sample Rate",
        "设置加速度计和陀螺仪的目标采样频率":
            "Set the requested accelerometer and gyroscope sample rate.",
        "动态 RMS": "Dynamic RMS",
        "近期峰值": "Recent Peak",
        "实际采样频率": "Actual Sample Rate",
        "此机型没有对应硬件": "This Mac does not contain this sensor.",
        "检测到硬件，但无法访问":
            "The sensor was detected, but it could not be opened.",
        "此机型没有可访问的机身运动传感器":
            "This Mac does not expose a chassis motion sensor.",
        "检测到机身运动传感器，但当前无法访问":
            "A chassis motion sensor was detected, but it could not be opened.",
        "等待传感器数据…": "Waiting for sensor data…",
        "正在读取传感器数据…": "Reading sensor data…",
        "等待首次读取": "Waiting for first reading",
        "正在读取": "Reading…",
        "风扇 1": "Fan 1",
        "风扇 2": "Fan 2",
        "传感器 1": "Sensor 1",
        "传感器 2": "Sensor 2",
        "传感器 3": "Sensor 3",
        "最低转速": "Minimum Speed",
        "目标转速": "Target Speed",
        "最高转速": "Maximum Speed",
        "它可以理解为 Mac 感受到的“推、拉和震动”。X、Y、Z 分别代表机身三个方向；即使电脑静止，传感器也会读到地球重力，所以其中一个方向通常接近 1 g，三个方向合起来也大约是 1 g。移动电脑、敲击桌面或扬声器振动时，数字会立即变化。":
            "Think of this as the push, pull, and vibration felt by the Mac. X, Y, and Z represent its three physical axes. Even at rest, gravity produces roughly 1 g across the combined axes. Move the Mac, tap the desk, or play bass-heavy audio and the readings respond immediately.",
        "它测量 Mac 正在“转得多快”，而不是已经转到了多少度。X、Y、Z 对应绕机身三个方向旋转，单位 °/s 表示每秒旋转多少度。电脑静止时应接近 0；抬起、转动或晃动电脑时，数值会增大。":
            "This measures how quickly the Mac is rotating, not its final angle. X, Y, and Z correspond to rotation around each chassis axis, in degrees per second. A stationary Mac should sit near zero; lifting, turning, or rocking it increases the readings.",
        "表示机身向左或向右倾斜的角度。可以把它想象成飞机左右压低机翼：水平放置时通常接近 0°，左侧或右侧抬高时会向正值或负值变化。":
            "The Mac's side-to-side tilt, like an aircraft lowering one wing. It should be near 0° on a level surface and moves positive or negative as either side is raised.",
        "表示机身前端或后端抬起的角度。可以把它想象成飞机抬头或低头：水平放置时通常接近 0°，垫高掌托或转轴一侧时会变化。":
            "The front-to-back tilt, similar to an aircraft pitching up or down. It should be near 0° on a level surface and changes when the palm-rest or hinge side is raised.",
        "表示 Mac 在桌面上向左或向右转了多少度。它把本次启动高级传感器时的朝向当作 0°，之后通过陀螺仪不断累加旋转量。这里没有磁力计帮助校正方向，所以它不是指南针；即使电脑不动，误差也会慢慢累积，数值可能随时间轻微漂移。":
            "The Mac's relative left or right rotation on the desk. The heading at sensor startup becomes 0°, then gyroscope movement is accumulated from there. With no magnetometer correction this is not a compass, and small errors will gradually drift over time.",
        "这条曲线把三个方向的动态加速度合成一个容易观察的震动强度。程序会尽量扣除静止时约 1 g 的重力影响；曲线越高，表示机身在最近一刻震动得越明显。敲击桌面、移动电脑、扬声器播放低频声音或附近设备运转都可能让曲线上升。":
            "This graph combines dynamic acceleration on all three axes into a single vibration signal. The app removes most of the roughly 1 g gravity component. Desk taps, moving the Mac, bass from the speakers, or nearby machinery can all raise the trace.",
        "表示程序每秒实际收到多少次传感器读数。比如 100 Hz 大约等于每秒读取 100 次。频率越高，越容易捕捉短促震动，但会产生更多数据和少量额外开销。由于系统调度和硬件节奏，实际值与所选目标相差一两次属于正常现象。":
            "The number of samples actually received each second. A 100 Hz reading is roughly 100 samples per second. Higher rates capture shorter vibrations but create more data and a little extra overhead. Small differences from the selected rate are normal.",

        "屏幕铰链、环境照度和颜色通道":
            "Display hinge, illuminance, and ambient spectral channels",
        "屏幕角度": "Display Angle",
        "等待数据": "Waiting…",
        "此机型没有可访问的屏幕角度传感器":
            "This Mac does not expose a display-angle sensor.",
        "环境光": "Ambient Light",
        "实际照度": "Illuminance",
        "此机型没有返回可访问的照度数据":
            "This Mac does not expose a readable illuminance value.",
        "ALS 归一化强度": "Normalized ALS Intensity",
        "此机型不提供原始光谱通道":
            "Raw spectral channels are not exposed on this Mac.",
        "此机型不提供可访问的原始光谱通道":
            "This Mac does not expose raw ambient-light spectral channels.",
        "四路原始光谱通道": "Four Raw Spectral Channels",
        "它表示屏幕与键盘底座之间大约张开了多少度。屏幕合上时接近 0°，正常使用时通常在 90° 到 130° 左右。这个隐藏传感器的原始报告只提供整数度，所以界面不显示小数；轻微晃动或铰链结构也可能让读数在相邻两度之间跳动。":
            "The approximate angle between the display and keyboard deck. A closed Mac is near 0°, while normal use is often around 90°–130°. The hidden sensor reports whole degrees only, so small movements may make the value hop between neighboring numbers.",
        "环境光传感器位于屏幕附近，用来判断周围环境是明亮还是昏暗。macOS 通常利用它调节自动亮度和键盘背光。遮住传感器、靠近窗户或打开台灯时，读数会明显变化。":
            "The ambient-light sensor sits near the display and measures how bright the surroundings are. macOS uses it for automatic display brightness and keyboard backlighting. Covering the sensor, moving near a window, or switching on a lamp should change the readings.",
        "lux 是照度单位，描述落在一个表面上的可见光有多强。数值越高代表环境越亮：昏暗房间可能只有几十 lux，普通室内通常是几百 lux，阳光下会高得多。这里的数值来自 Mac 自己的环境光传感器，不是专业校准仪器。":
            "Lux measures visible light falling on a surface. A dim room may be only a few dozen lux, ordinary indoor lighting a few hundred, and daylight far higher. This is the Mac's own sensor, not a calibrated light meter.",
        "这是环境光传感器内部使用的原始强度数值，可以用来比较“现在比刚才更亮还是更暗”。它没有公开、稳定的物理单位，因此不能当作 lux，也不适合拿来和专业照度计直接比较。":
            "A raw normalized intensity used inside the ambient-light sensor. It is useful for comparing whether the room became brighter or darker, but it has no documented physical unit and should not be treated as lux.",
        "Mac 的环境光传感器会同时返回四组原始计数，不同光源会形成不同的四路比例。Apple 没有公开 CH1–CH4 分别对应哪段波长，所以它们不能直接叫作红、绿、蓝，也不能准确还原颜色。它们更适合用来比较窗外日光、暖色台灯和冷色屏幕等光源之间的相对差异。":
            "The ambient-light sensor reports four raw channel counts. Different light sources produce different ratios, but Apple has not documented the wavelength represented by CH1–CH4. They are not simply red, green, and blue; use them to compare relative signatures from daylight, warm lamps, and cooler displays.",

        "位置、压力和电容数据；压力单位为未经物理标定的相对值":
            "Position, pressure, and capacitance data. Pressure is an uncalibrated relative value.",
        "设备信息": "Device Information",
        "感应表面": "Sensing Surface",
        "传感阵列": "Sensor Matrix",
        "原始数据流": "Raw Data Stream",
        "可读取": "Available",
        "实时触摸面板": "Live Touch Surface",
        "压力趋势（相对值）": "Pressure Trend (Relative)",
        "当前读数": "Current Readings",
        "触点数": "Touches",
        "最大压力": "Peak Pressure",
        "压力": "Pressure",
        "接触密度": "Contact Density",
        "相对值": "relative",
        "总电容": "Total Capacitance",
        "当前触点": "Active Touches",
        "压力是触控板报告的相对按压强度；接触密度是驱动根据手指接触面积和电容分布计算的内部相对值。两者都没有公开的物理单位，适合观察同一次触摸中的相对变化，不能直接换算成重量或压强。":
            "Pressure is the trackpad's relative press intensity. Contact density is an internal relative value derived from contact area and capacitive distribution. Neither has a documented physical unit, so they are useful for comparing changes within a touch but cannot be converted directly into weight or physical pressure.",
        "等待触控板输入": "Waiting for trackpad input",
        "触摸触控板以查看原始压力数据": "Touch the trackpad to see raw pressure data",
        "触控板不可用": "Trackpad Unavailable",
        "没有找到可由 MultitouchSupport 访问的内置触控板。":
            "No built-in trackpad accessible through MultitouchSupport was found.",
        "触控板私有接口返回的是百分之一毫米量级的整数，例如 12480 × 7680 对应约 124.8 × 76.8 mm。这里换算后显示感应区域的近似物理尺寸；它不是屏幕像素，也不是触点使用的 0–1 归一化坐标。":
            "The private trackpad API reports integer dimensions at roughly one-hundredth-millimeter scale. For example, 12480 × 7680 is shown as approximately 124.8 × 76.8 mm. This is the approximate sensing area, not screen pixels or the normalized 0–1 touch coordinates.",
        "触控板内部电容感应网格的行数与列数。系统结合多个感应单元的变化，估算手指位置、接触面积、移动方向和触摸强弱。":
            "The rows and columns in the trackpad's capacitive sensing grid. Changes across multiple cells are combined to estimate position, contact area, direction, and touch intensity.",
        "表示应用是否已成功连接触控板的原始多点数据流。可读取时能获得触点位置、接触面积和内部相对压力。不同 MacBook 的触控板结构并不完全相同，例如 MacBook Neo 使用机械式多点触控板，因此这里不把数据流等同于 Force Touch。":
            "Whether the app connected to the raw multitouch stream. It can provide touch position, contact area, and an internal relative pressure value. Trackpad hardware differs between MacBooks; for example, MacBook Neo uses a mechanical multitouch trackpad, so the app does not equate this stream with Force Touch.",
        "这是触控板报告的内部相对压力，不是牛顿或克。它适合比较同一根手指按得更轻还是更重，但不同手指、接触面积和触点位置都会影响数值。只有经过已知重量校准后，实验性电子秤功能才可能换算成克。":
            "The trackpad's internal relative pressure value, not newtons or grams. It can compare lighter and harder presses from the same finger, but finger choice, contact area, and location all affect it. Converting it to weight would require calibration against known masses.",
        "当前所有触点中最大的原始压力值。它没有公开的物理单位，只能用于观察相对变化，不能直接解释为重量。":
            "The highest raw pressure among active touches. It has no documented physical unit and cannot be interpreted directly as weight.",
        "触控板对所有触点报告的电容总量。手指接触面积、皮肤状态和压力都会影响它，因此它常与压力一起用于判断接触强弱。":
            "The combined capacitance reported for all touches. Contact area, skin condition, and pressure all affect it, so it is best read alongside pressure.",

        "来自 SMC 与 HID Sensor Hub 的温度传感器":
            "Temperature sensors reported by the SMC and HID Sensor Hub",
        "温度传感器": "Temperature Sensors",
        "当前机型没有返回温度数据。": "This Mac did not return temperature data.",
        "此机型没有返回可访问的温度传感器":
            "This Mac does not expose readable temperature sensors.",
        "检测到温度传感器，但当前无法读取":
            "Temperature sensors were detected, but their readings are unavailable.",
        "处理器": "CPU",
        "图形处理器": "GPU",
        "电池与供电": "Battery & Power",
        "机身与环境": "Chassis & Ambient",
        "主板与 SoC": "Logic Board & SoC",
        "这一组主要来自 CPU 核心、CPU 集群、封装和热管附近。短时间高温通常是高负载的正常结果；更值得关注的是温度是否长期维持很高，以及系统是否同时出现风扇高速或性能下降。":
            "Primarily CPU cores, clusters, package sensors, and areas near the heat pipe. Brief high temperatures are normal under load; sustained heat combined with high fan speed or reduced performance is more informative.",
        "这一组反映 GPU 核心、图形互连和散热部件附近的温度。运行游戏、视频处理、三维渲染或机器学习任务时通常会明显升高。":
            "GPU cores, graphics interconnects, and nearby cooling components. Games, video processing, 3D rendering, and machine-learning workloads commonly raise these temperatures.",
        "这一组反映统一内存、内存附近区域和供电调节器的温度。大量读写、图形任务或持续高负载时可能升高。":
            "Unified memory, nearby board areas, and related power regulation. Heavy memory traffic, graphics work, and sustained load can raise these readings.",
        "这一组来自 SSD、NAND 闪存和存储控制器。复制大文件、安装软件或进行大量磁盘读写时，温度通常会上升。":
            "SSD, NAND flash, and storage-controller sensors. Large file transfers, installations, and sustained disk I/O normally raise these temperatures.",
        "这一组来自电池、电源管理和 USB-C 供电芯片。充电、连接高功率适配器或整机负载较高时，部分传感器会升温。":
            "Battery, power-management, and USB-C power-delivery sensors. Charging, high-wattage adapters, and heavy system load may warm this group.",
        "这一组位于机身边缘、进出风区域、接口和环境附近，更接近你可能触摸到的外壳或周围空气温度。":
            "Sensors near the chassis edges, airflow paths, ports, and ambient areas. These are closer to the enclosure and surrounding air you can actually feel.",
        "这一组包含 SoC 内部、PMU、主板二极管和虚拟汇总传感器。名称较底层，主要用于观察整体热分布，不建议只凭单个编号判断硬件状态。":
            "Internal SoC, PMU, logic-board diode, and virtual aggregate sensors. Their names are low-level; use the group to observe thermal distribution rather than diagnosing hardware from one numbered reading.",
        "组内最高": "Group high",
        "采集提示": "Collector Notes",
        "当前机型没有返回这一类数据。": "This Mac did not return data for this category.",

        "当前转速、目标转速与硬件限制":
            "Current speed, target speed, and hardware limits",
        "实时转速": "Live Fan Speed",
        "正在读取实时转速…": "Reading live fan speed…",
        "转速范围": "Fan Range",
        "这是风扇此刻真正的转速，单位为 RPM（每分钟转数）。0 RPM 表示风扇当前停转，属于 Apple Silicon Mac 在温度较低时的正常状态；负载或温度升高后，转速会自动上升。":
            "The fan's actual current speed in revolutions per minute. A reading of 0 RPM is normal on Apple silicon Macs when temperatures are low; fan speed rises automatically with sustained heat or load.",
        "此机型采用无风扇设计，没有风扇硬件":
            "This Mac uses a fanless design and has no fan hardware.",
        "检测到风扇硬件，但当前无法访问":
            "Fan hardware was detected, but its readings are unavailable.",

        "电池状态、寿命记录、供电来源和 USB-C PD 信息":
            "Battery condition, lifetime records, power source, and USB-C PD details",
        "电量": "Charge",
        "循环次数": "Cycle Count",
        "当前温度": "Current Temperature",
        "实时功率": "Live Power",
        "供电来源": "Power Source",
        "外接电源": "Power Adapter",
        "电池供电": "Battery",
        "充电状态": "Charging",
        "正在充电": "Charging",
        "未充电": "Not Charging",
        "历史极值": "Historical Extremes",
        "最低温度": "Lowest Temperature",
        "最高温度": "Highest Temperature",
        "最大充电电流": "Peak Charge Current",
        "最大放电电流": "Peak Discharge Current",
        "容量": "Capacity",
        "设计容量": "Design Capacity",
        "最大容量": "Maximum Capacity",
        "补偿容量": "Compensated Capacity",
        "当前原始电量": "Raw Current Charge",
        "健康度": "Health",
        "电芯状态": "Cell Status",
        "未读取到电芯数据。": "No battery-cell data was reported.",
        "充电器与实时输入": "Power Adapter & Live Input",
        "未连接充电器": "No power adapter connected",
        "额定功率": "Rated Power",
        "协商电压": "Negotiated Voltage",
        "协商上限电流": "Negotiated Current Limit",
        "实时输入功率": "Live Input Power",
        "实时输入电压": "Live Input Voltage",
        "实时输入电流": "Live Input Current",
        "充电器公布的 USB-C PD 档位": "USB-C PD Profiles Advertised by the Adapter",
        "当前没有可显示的 PD 档位。": "No USB-C PD profiles are currently available.",
        "当前": "Active",
        "电池管理系统估算的剩余电量百分比。它是根据电池电压、电流和历史状态计算的估计值，短时间内不一定线性变化。":
            "The battery management system's estimate of remaining charge, calculated from voltage, current, and recent history. It may not move linearly over short periods.",
        "累计使用相当于 100% 电池容量算一个循环，不要求一次从满电用到没电。例如两次各使用 50%，大约合计一个循环。":
            "Using a cumulative 100% of battery capacity counts as one cycle. It does not need to happen in one discharge; two 50% uses add up to roughly one cycle.",
        "电池组当前温度。充电、持续高负载和较高环境温度都会让它升高。与单次峰值相比，长时间处在高温环境对电池寿命更值得关注。":
            "Current battery-pack temperature. Charging, sustained load, and warm surroundings all raise it. Long periods at high temperature matter more to battery life than a brief peak.",
        "这是用电池实时电压乘以电流估算出的功率，并取绝对值方便阅读。它可以粗略理解为电池此刻充入或输出能量的速度：数值越大，通常代表充电更快，或电脑正在消耗更多电量。":
            "Estimated from live battery voltage multiplied by current, shown as an absolute value. Higher power usually means faster charging or greater system consumption.",
        "显示 Mac 当前是否检测到充电器或其他外接供电。接入电源不一定代表正在给电池充电，系统也可能只使用外部电源维持运行。":
            "Whether the Mac detects an adapter or another external power source. External power does not necessarily mean the battery is charging; the Mac may simply be running from the adapter.",
        "显示电池此刻是否正在接收充电电流。即使接着充电器，电量已满、电池温度较高或系统启用优化充电时，也可能显示未充电。":
            "Whether the battery is currently accepting charge. A connected adapter may still show Not Charging when the battery is full, warm, or held by optimized charging.",
        "电池管理系统提供的 NominalChargeCapacity。它经过平滑处理，用于表示电池当前预计充满时可容纳的电量。新电池可能略高于标称设计容量。":
            "NominalChargeCapacity reported by the battery management system. It is a smoothed estimate of how much charge the battery can currently hold when full. A new battery may exceed its rated design capacity.",
        "底层 AppleRawMaxCapacity，也称补偿后的满充容量。它会随温度、荷电状态和电池模型校准发生短期波动，因此不再直接用于计算系统健康度。":
            "The lower-level AppleRawMaxCapacity, also described as compensated full-charge capacity. It can fluctuate with temperature, charge state, and battery-model calibration, so it is not used directly for the health percentage.",
        "使用最大容量除以设计容量得到的实际比例，不再封顶为 100%。新电池实际容量高于标称设计容量时，健康度可能显示为 100% 以上。":
            "Maximum capacity divided by design capacity, with no 100% cap. A new battery that exceeds its rated design capacity may report health above 100%.",

        "SSD 寿命、终身总读写量与本次开机的底层 I/O":
            "SSD endurance, lifetime reads and writes, and I/O since boot",
        "读取终身 SMART 数据 🤫": "Read Lifetime SMART Data 🤫",
        "正在读取存储设备": "Reading Storage Devices",
        "首次读取通常需要几秒。": "The first scan can take a few seconds.",
        "本次已读取": "Read This Boot",
        "本次已写入": "Written This Boot",
        "数据说明": "How to Read This Data",
        "终身 SMART 统计": "Lifetime SMART Statistics",
        "启用隐藏传感器后显示健康度和终身总读写量。":
            "Enable hidden sensors to read drive health and lifetime I/O.",
        "磁盘健康度": "Drive Health",
        "已用寿命": "Endurance Used",
        "终身总 I/O": "Lifetime Total I/O",
        "终身总读取": "Lifetime Reads",
        "终身总写入": "Lifetime Writes",
        "通电时间": "Power-On Time",
        "通电次数": "Power Cycles",
        "异常断电": "Unsafe Shutdowns",
        "介质错误": "Media Errors",
        "可用备用空间": "Available Spare",
        "本次开机以来的 I/O": "I/O Since Boot",
        "已读取": "Read",
        "已写入": "Written",
        "读取操作": "Read Operations",
        "写入操作": "Write Operations",
        "读取错误": "Read Errors",
        "写入错误": "Write Errors",
        "健康度按 NVMe SMART 的 Percentage Used 计算：健康度 = 100% − 已用寿命。它反映 SSD 额定写入寿命的消耗程度，不是故障概率，也不能保证磁盘不会突然损坏。终身读写量来自 SSD 自身累计计数，本次开机 I/O 来自 macOS 驱动层，两者统计口径不同。":
            "Drive health is calculated from the NVMe Percentage Used field: health equals 100% minus endurance used. It describes rated write endurance, not failure probability, and cannot guarantee that a drive will not fail unexpectedly. Lifetime reads and writes come from the SSD controller; since-boot I/O comes from the macOS driver, so the two sets use different accounting.",
        "需要管理员权限读取 NVMe SMART 寿命和终身读写计数":
            "Administrator access is required to read NVMe endurance and lifetime I/O counters.",
        "这些计数由 SSD 控制器保存，不会在普通重启后归零。读取 Apple 内置 NVMe SSD 的完整 SMART 数据需要管理员授权。":
            "These counters are stored by the SSD controller and survive normal restarts. Reading complete SMART data from Apple's internal NVMe storage requires administrator approval.",
        "按 NVMe 标准的已用寿命字段计算：100% 减去 Percentage Used。它代表额定耐久度余量，不是故障概率。":
            "Calculated from the NVMe Percentage Used field: 100% minus endurance used. It represents rated endurance remaining, not the probability of failure.",
        "SSD 从投入使用以来累计的数据读取量与写入量之和。NVMe 以 512,000 字节为一个 Data Unit 进行统计。":
            "Total data read and written over the SSD's lifetime. NVMe records these values in 512,000-byte data units.",
        "SSD 记录的非正常断电或未完成标准关机流程的次数。系统崩溃、强制断电等情况都可能增加该值。":
            "The number of power losses that did not complete a normal shutdown path. Crashes and forced power-offs can increase this counter.",
        "这些数值从本次 macOS 启动后开始累计，重启会归零；它们不是硬盘出厂以来的终身写入量。":
            "These counters begin at the current macOS boot and reset after a restart. They are not lifetime drive totals.",

        "当前 IP、Wi-Fi 协议、网络流量和 USB-C / 雷雳连接状态":
            "Current IP addresses, Wi-Fi link, network traffic, and USB-C / Thunderbolt status",
        "网络状态": "Network Status",
        "连接状态": "Connection",
        "已连接": "Connected",
        "未连接": "Disconnected",
        "活动接口": "Active Interface",
        "当前 IPv4": "Current IPv4",
        "当前 IPv6": "Current IPv6",
        "VPN 隧道": "VPN Tunnels",
        "未检测到": "None detected",
        "Wi-Fi 状态": "Wi-Fi Status",
        "网络名称": "Network Name",
        "允许定位权限后显示": "Allow Location access to show the SSID",
        "无线协议": "Wi-Fi Standard",
        "信道": "Channel",
        "发送速率": "Transmit Rate",
        "信号 / 噪声": "Signal / Noise",
        "网络安全": "Security",
        "活动网络接口": "Active Network Interfaces",
        "USB-C 与雷雳接口": "USB-C & Thunderbolt Ports",
        "未读取到 USB-C / 雷雳端口状态。": "No USB-C or Thunderbolt port status was reported.",
        "已连接设备": "Connected device",
        "未连接设备": "No device connected",
        "已连接外设": "Connected Peripherals",
        "当前没有通过 USB 或雷雳识别到外接设备。":
            "No external USB or Thunderbolt devices are currently reported.",
        "本次开机已接收": "Received Since Boot",
        "本次开机已发送": "Sent Since Boot",
        "只根据当前活动网络接口及其 IP 地址判断，不会向互联网发送探测请求。":
            "Determined from active interfaces and their IP addresses. The app sends no connectivity probe to the internet.",
        "这是 Mac 当前网络接口的本机 IPv4 地址，不一定是路由器之外可见的公网 IP。":
            "The local IPv4 address assigned to this Mac. It is not necessarily the public address visible beyond your router.",
        "显示首个非链路本地 IPv6 地址。仅以 fe80 开头的本地链路地址不会在这里显示。":
            "Shows the first non-link-local IPv6 address. Local fe80 addresses are omitted.",
        "根据活动的 utun 系统隧道接口统计。部分 Apple 系统服务也可能使用 utun，因此它不一定全部来自传统 VPN 软件。":
            "Counted from active utun tunnel interfaces. Some Apple services also use utun, so not every entry necessarily belongs to a conventional VPN app.",
        "SSID 等无线网络信息可能受 macOS 定位服务和隐私权限影响；协议、信道和速率以系统当前报告为准。":
            "SSID details may be limited by macOS Location Services and privacy permissions. Standards, channels, and rates reflect the current system report.",
        "macOS 要求应用获得定位权限后才能读取当前 Wi-Fi 名称。应用只在本机显示名称，不记录或上传位置信息。":
            "macOS requires Location permission before an app can read the current Wi-Fi name. Mac Unseen displays it locally and never records or uploads location data.",
        "例如 802.11ax 对应 Wi-Fi 6 / 6E，802.11ac 对应 Wi-Fi 5。具体是否为 6E 还取决于当前频段。":
            "For example, 802.11ax maps to Wi-Fi 6 or 6E, while 802.11ac maps to Wi-Fi 5. Whether a link is 6E also depends on its current band.",
        "这是无线链路当前协商或报告的发送速率，不等同于实际下载速度。":
            "The current negotiated or reported Wi-Fi transmit rate. It is not the same as real download throughput.",
        "通常以 dBm 表示。信号越接近 0 越强，信号与噪声之间的差距越大，一般代表链路质量越好。":
            "Usually reported in dBm. Signal values closer to zero are stronger, and a larger gap between signal and noise generally means a cleaner link.",
        "收发流量从本次开机后开始累计，接口重建或系统重启后可能重新计数。":
            "Traffic counters accumulate from the current boot and may reset when an interface is recreated or macOS restarts.",
        "断开时显示的是端口能力上限；连接后显示系统实际识别到的设备和报告速度。仅凭 40 Gb/s 有时无法可靠区分雷雳 3、雷雳 4 与 USB4，因此不会强行猜测版本。":
            "A disconnected port shows its reported capability. Once connected, the app shows the device and speed detected by macOS. A 40 Gb/s link alone cannot always distinguish Thunderbolt 3, Thunderbolt 4, and USB4, so the app does not guess.",

        "进入感应区": "Entered range",
        "悬停": "Hovering",
        "开始触摸": "Touch began",
        "触摸中": "Touching",
        "离开表面": "Leaving surface",
        "仍在感应区": "Still in range",
        "已离开": "Exited",
        "未跟踪": "Untracked",
        "发现 I/O 错误": "I/O errors detected",
        "未提供 SMART": "SMART unavailable",
        "存储设备": "Storage Device",
        "USB 设备": "USB Device",
        "USB 接口": "USB Port",
        "USB-C / 雷雳接口": "USB-C / Thunderbolt Port",
        "物理网络接口": "Physical Network Interface",
        "网络桥接": "Network Bridge",
        "网络接口": "Network Interface",
        "接口": "Port",
        "外接设备": "Peripheral",
        "未启动": "Not started",
        "未知频段": "Unknown band",
        "开放网络": "Open network",
        "WPA 个人": "WPA Personal",
        "WPA2 个人": "WPA2 Personal",
        "WPA/WPA2 个人": "WPA/WPA2 Personal",
        "动态 WEP": "Dynamic WEP",
        "WPA 企业": "WPA Enterprise",
        "WPA2 企业": "WPA2 Enterprise",
        "WPA/WPA2 企业": "WPA/WPA2 Enterprise",
        "WPA3 个人": "WPA3 Personal",
        "WPA3 企业": "WPA3 Enterprise",
        "WPA2/WPA3 过渡": "WPA2/WPA3 Transition",
        "增强开放网络": "Enhanced Open",

        "应用资源不完整，请重新构建应用。": "App resources are incomplete. Rebuild the application.",
        "等待管理员授权…": "Waiting for administrator approval…",
        "正在连接": "Connecting",
        "已请求停止高级传感器。": "The hidden-sensor collector has been asked to stop.",
        "高级传感器正在启动，通常需要 1–3 秒。": "Hidden sensors are starting. This usually takes 1–3 seconds.",
        "管理员授权已取消。": "Administrator approval was cancelled.",

        "数据边界": "Data & Privacy",
        "应用只读取传感器。首版不会设置风扇转速、修改屏幕或键盘亮度、运行快捷指令，也不会上传数据。管理员辅助进程退出后不会安装常驻服务。":
            "Mac Unseen only reads sensors. It does not control fans, change display or keyboard brightness, run Shortcuts, or upload telemetry. The administrator helper installs no background service and exits with the app.",
        "开源组件": "Open-Source Components",
        "Apple SPU 读取基于 olvvier/apple-silicon-accelerometer 的逆向研究。":
            "Apple SPU access builds on reverse-engineering work from olvvier/apple-silicon-accelerometer.",
        "触控板结构与接口参考 Kyome22/OpenMultitouchSupport。":
            "Trackpad structures and interfaces reference Kyome22/OpenMultitouchSupport.",
        "SMC/HID 遥测由 dkorunic/iSMC 提供，按 GPL-3.0 分发。":
            "SMC and HID telemetry is provided by dkorunic/iSMC under GPL-3.0.",
        "完整许可证位于应用包 Contents/Resources/Licenses。":
            "Full license texts are included in Contents/Resources/Licenses.",
        "这些接口未由 Apple 公开，系统更新后可能失效。":
            "These interfaces are undocumented by Apple and may break after a macOS update.",

        "正常": "Normal",
        "轻度升温": "Elevated",
        "较高": "High",
        "严重": "Critical",
        "未知": "Unknown",
        "是": "Yes",
        "否": "No",
        "未报告": "Not reported",
        "已启用": "Enabled",
        "未启用": "Disabled",
        "次": "times",
        "个活动接口": " active interfaces",
    ]
}
