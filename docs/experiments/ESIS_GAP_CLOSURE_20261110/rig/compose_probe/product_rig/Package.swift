// swift-tools-version:5.9
import PackageDescription

// 组成性探针产品路径装置的临时包：只引用产品仓的 SimiGoRuntime 包，
// 不改动产品仓任何文件（绕过 app 主工程 mlx 子模块解析的已验证路径，同 P1 的 /tmp/e 做法）。
let package = Package(
    name: "turn-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 仓内相对路径（本目录 → docs/experiments/ESIS_GAP_CLOSURE_20261110/rig/... → 仓根）
        .package(path: "../../../../../../Packages/SimiGoRuntime")
    ],
    targets: [
        .executableTarget(
            name: "turn-cli",
            dependencies: [.product(name: "SimiGoRuntimeContract", package: "SimiGoRuntime")])
    ])
