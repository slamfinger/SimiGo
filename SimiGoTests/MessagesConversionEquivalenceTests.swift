import XCTest
@testable import SimiGo

/// #8 审计回归：JSONValue.any 逐元素转换必须与旧「data → JSONDecoder」
/// 路径在**宽 JSON 类型空间**上逐值等价——生产请求的类型空间比手写断言
/// 矩阵更宽，这里用差分法对每条语料同时跑两条路径并比对完整 JSONValue 树。
///
/// 两条路径的机制差异正是风险所在：
///   旧：重新序列化 → JSONDecoder（Bool 按 CFBoolean 身份判别，数字走 Double）
///   新：NSNumber 条件转型（`as? Bool` 按 objCType 判别，再落 NSNumber→Double）
final class MessagesConversionEquivalenceTests: XCTestCase {
    /// 覆盖类型空间边界的语料。每条是一个 messages 数组的 JSON 文本。
    static let corpus: [String] = [
        // 布尔在各位置（对象值 / 数组元素 / 深嵌套）
        #"[{"role":"user","flag":true},{"role":"user","flag":false},{"role":"user","nested":{"deep":[true,false,{"x":true}]}}]"#,
        // 整数尺寸阶梯（含 Int32 边界、2^53±1 精度边界、Int64 max）
        #"[{"n":0},{"n":1},{"n":-1},{"n":2147483647},{"n":2147483648},{"n":9007199254740991},{"n":9007199254740993},{"n":9223372036854775807}]"#,
        // 浮点与指数
        #"[{"f":1.5},{"f":-0.25},{"f":1e10},{"f":1.5e-10},{"f":0.1}]"#,
        // 看似布尔的字符串与数字（必须保持 string/number，不得折叠）
        #"[{"s1":"true","s2":"false","s3":"0","s4":"1","n1":true,"n2":0}]"#,
        // null 全位置
        #"[{"a":null,"b":{"c":null},"d":[null,null]},{"role":null,"content":null}]"#,
        // 空容器与深嵌套（10 层）
        #"[{"e1":{},"e2":[]},{"l":{"l":{"l":{"l":{"l":{"l":{"l":{"l":{"l":{"l":{"bottom":1}}}}}}}}}}}]"#,
        // 混合类型数组
        #"[{"mix":[1,"a",true,null,{},[],2.5,false]}]"#,
        // Unicode / 转义 / emoji / 键名转义
        #"[{"中文键":"值🎉","esc":"引号\"反斜杠\\换行\n制表\t","key\\path":"v"}]"#,
        // 数值字符串形态的 tool arguments（OpenAI wire 形态）
        #"[{"role":"assistant","tool_calls":[{"id":"c1","type":"function","function":{"name":"f","arguments":"{\"x\":true,\"k\":[1,2]}"}}]}]"#,
        // 非 object 元素（旧路径接受并转为标量 JSONValue）
        #"["plain",7,false,null,{"role":"user"}]"#,
        // 大数组
        "[" + (0..<64).map { #"{"i":\#($0),"pad":"x\#($0)"}"# }.joined(separator: ",") + "]",
    ]

    /// 旧路径复刻（与改动前 HTTPServerChat 逐机制一致）：
    /// JSONSerialization.data(withJSONObject:) → JSONDecoder().decode([JSONValue])
    private func oldPath(_ rawMessages: [Any]) throws -> [JSONValue] {
        let messageData = try JSONSerialization.data(withJSONObject: rawMessages)
        return try JSONDecoder().decode([JSONValue].self, from: messageData)
    }

    /// 新路径复刻（与改动后逐机制一致）：
    /// json["messages"] as? [Any] → 逐元素 JSONValue.any
    private func newPath(_ rawMessages: [Any]) -> [JSONValue] {
        rawMessages.map { JSONValue.any($0) }
    }

    func testAnyConversionMatchesDecoderPathAcrossTypeCorpus() throws {
        for (index, corpusJSON) in Self.corpus.enumerated() {
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(corpusJSON.utf8)),
                "corpus[\(index)] 本身必须可解析"
            )
            let rawMessages = try XCTUnwrap(body as? [Any], "corpus[\(index)] 须为 JSON 数组")

            let old = try oldPath(rawMessages)
            let new = newPath(rawMessages)

            XCTAssertEqual(new, old, "corpus[\(index)] 两路径不等价\nold=\(old)\nnew=\(new)")
        }
    }

    /// JSONSerialization 输出的 NSNumber 子类空间（bool/int/double）显式对拍，
    /// 不依赖 JSON 文本语料碰巧覆盖。
    func testAnyConversionHandlesNSNumberVariants() {
        let direct: [Any] = [
            NSNumber(value: true), NSNumber(value: false),
            NSNumber(value: Int32.max), NSNumber(value: Int64.max),
            NSNumber(value: Double.pi), NSNumber(value: 0),
            NSNull(),
        ]
        let converted = direct.map { JSONValue.any($0) }

        guard case .bool(true) = converted[0] else {
            return XCTFail("boolean NSNumber 必须转 .bool(true)，得 \(converted[0])")
        }
        guard case .bool(false) = converted[1] else {
            return XCTFail("boolean NSNumber 必须转 .bool(false)，得 \(converted[1])")
        }
        // 数值型 NSNumber（含 0）必须走 .number 分支，不得被 Bool 分支吞掉
        for value in converted.dropFirst(2).dropLast() {
            guard case .number = value else { return XCTFail("数值 NSNumber 必须转 .number，得 \(value)") }
        }
        guard case .null = converted[6] else { return XCTFail("NSNull 必须转 .null") }
    }
}
