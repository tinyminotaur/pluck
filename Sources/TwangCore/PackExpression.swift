import Foundation

/// A tiny, safe expression language for community animation packs: arithmetic, comparisons, a handful of maths
/// functions and named variables. There are no loops, no assignment and no I/O, and every expression is size-limited,
/// so a pack can only ever compute numbers.
public struct PackExpression: Sendable {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case syntax(String), unknownVariable(String), unknownFunction(String), wrongArguments(String), tooLong, tooComplex
        public var description: String {
            switch self {
            case .syntax(let s): return "syntax error: \(s)"
            case .unknownVariable(let v): return "unknown variable '\(v)'"
            case .unknownFunction(let f): return "unknown function '\(f)'"
            case .wrongArguments(let f): return "wrong number of arguments to '\(f)'"
            case .tooLong: return "expression is too long"
            case .tooComplex: return "expression is too complex"
            }
        }
    }

    public static let maxLength = 400
    public static let maxNodes = 240

    fileprivate indirect enum Node: Sendable {
        case num(Double)
        case v(Int)
        case neg(Node), not(Node)
        case bin(Character, Node, Node)       // + - * / % ^ < > l(<=) g(>=) = (==) ! (!=) & |
        case call(Fn, [Node])
        case cond(Node, Node, Node)
    }

    fileprivate enum Fn: String, Sendable, CaseIterable {
        case sin, cos, tan, abs, min, max, clamp, smoothstep, mix, lerp, pow, sqrt, floor, fract, sign, noise, rand, tri, atan2, exp, step, round, ceil, saw
        var arity: ClosedRange<Int> {
            switch self {
            case .sin, .cos, .tan, .abs, .sqrt, .floor, .fract, .sign, .noise, .rand, .tri, .exp, .round, .ceil, .saw: return 1...1
            case .min, .max, .pow, .atan2, .step: return 2...2
            case .clamp, .smoothstep, .mix, .lerp: return 3...3
            }
        }
    }

    private let root: Node
    /// The variables this expression reads (indices into the environment), for diagnostics.
    public let usedVariables: Set<Int>

    /// Compile `source`; `variables` maps each allowed name to its slot in the environment array.
    public init(_ source: String, variables: [String: Int]) throws {
        guard source.count <= Self.maxLength else { throw ParseError.tooLong }
        var p = Parser(Array(source), variables)
        let node = try p.parseTop()
        guard p.nodes <= Self.maxNodes else { throw ParseError.tooComplex }
        root = node
        usedVariables = p.used
    }

    public init(constant: Double) { root = .num(constant); usedVariables = [] }

    public func eval(_ env: [Double]) -> Double {
        let v = Self.run(root, env)
        return v.isFinite ? v : 0
    }

    // MARK: Evaluation

    private static func hash(_ x: Double) -> Double {
        var h = UInt64(bitPattern: Int64((x * 1000).rounded()) &* 0x9E37_79B1 &+ 0x2545F491)
        h ^= h >> 15; h = h &* 0x2C1B_3C6D; h ^= h >> 12; h = h &* 0x297A_2D39; h ^= h >> 15
        return Double(h & 0xFFFFFF) / Double(0x1000000)
    }

    private static func run(_ n: Node, _ e: [Double]) -> Double {
        switch n {
        case .num(let d): return d
        case .v(let i): return i < e.count ? e[i] : 0
        case .neg(let a): return -run(a, e)
        case .not(let a): return run(a, e) == 0 ? 1 : 0
        case .cond(let c, let a, let b): return run(c, e) != 0 ? run(a, e) : run(b, e)
        case .bin(let op, let l, let r):
            let a = run(l, e)
            switch op {
            case "&": return a != 0 ? (run(r, e) != 0 ? 1 : 0) : 0
            case "|": return a != 0 ? 1 : (run(r, e) != 0 ? 1 : 0)
            default: break
            }
            let b = run(r, e)
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return b == 0 ? 0 : a / b
            case "%": return b == 0 ? 0 : a.truncatingRemainder(dividingBy: b)
            case "^": return pow(a, max(-32, min(32, b)))
            case "<": return a < b ? 1 : 0
            case ">": return a > b ? 1 : 0
            case "l": return a <= b ? 1 : 0
            case "g": return a >= b ? 1 : 0
            case "=": return a == b ? 1 : 0
            case "!": return a != b ? 1 : 0
            default: return 0
            }
        case .call(let f, let args):
            let a = args.map { run($0, e) }
            switch f {
            case .sin: return sin(a[0])
            case .cos: return cos(a[0])
            case .tan: return tan(a[0])
            case .abs: return Swift.abs(a[0])
            case .min: return Swift.min(a[0], a[1])
            case .max: return Swift.max(a[0], a[1])
            case .clamp: return Swift.max(a[1], Swift.min(a[2], a[0]))
            case .smoothstep:
                let t = Swift.max(0, Swift.min(1, (a[2] - a[0]) / (a[1] - a[0] == 0 ? 1 : a[1] - a[0])))
                return t * t * (3 - 2 * t)
            case .mix, .lerp: return a[0] + (a[1] - a[0]) * a[2]
            case .pow: return pow(a[0], Swift.max(-32, Swift.min(32, a[1])))
            case .sqrt: return a[0] <= 0 ? 0 : sqrt(a[0])
            case .floor: return Foundation.floor(a[0])
            case .ceil: return Foundation.ceil(a[0])
            case .round: return a[0].rounded()
            case .fract: return a[0] - Foundation.floor(a[0])
            case .sign: return a[0] > 0 ? 1 : (a[0] < 0 ? -1 : 0)
            case .rand: return hash(a[0])
            case .noise:
                let i = Foundation.floor(a[0]), f = a[0] - i
                let u = f * f * (3 - 2 * f)
                return hash(i) * (1 - u) + hash(i + 1) * u
            case .tri: let f = a[0] - Foundation.floor(a[0]); return f < 0.5 ? f * 2 : 2 - f * 2
            case .saw: return a[0] - Foundation.floor(a[0])
            case .atan2: return Foundation.atan2(a[0], a[1])
            case .exp: return Foundation.exp(Swift.max(-40, Swift.min(40, a[0])))
            case .step: return a[1] >= a[0] ? 1 : 0
            }
        }
    }

    // MARK: Parser

    private struct Parser {
        let s: [Character]
        let vars: [String: Int]
        var i = 0
        var nodes = 0
        var used = Set<Int>()
        static let constants: [String: Double] = ["pi": .pi, "tau": 2 * .pi, "e": M_E, "true": 1, "false": 0]

        init(_ s: [Character], _ vars: [String: Int]) { self.s = s; self.vars = vars }

        mutating func ws() { while i < s.count, s[i] == " " || s[i] == "\t" || s[i] == "\n" { i += 1 } }
        mutating func peek(_ c: Character) -> Bool { ws(); return i < s.count && s[i] == c }
        mutating func eat(_ c: Character) -> Bool { if peek(c) { i += 1; return true }; return false }
        mutating func eatStr(_ t: String) -> Bool {
            ws()
            let a = Array(t)
            guard i + a.count <= s.count, Array(s[i..<(i + a.count)]) == a else { return false }
            i += a.count; return true
        }
        mutating func make(_ n: Node) -> Node { nodes += 1; return n }

        mutating func parseTop() throws -> Node {
            let n = try ternary()
            ws()
            if i < s.count { throw ParseError.syntax("unexpected '\(s[i])'") }
            return n
        }
        mutating func ternary() throws -> Node {
            let c = try or()
            if eat("?") {
                let a = try ternary()
                guard eat(":") else { throw ParseError.syntax("expected ':'") }
                let b = try ternary()
                return make(.cond(c, a, b))
            }
            return c
        }
        mutating func or() throws -> Node {
            var l = try and()
            while eatStr("||") { l = make(.bin("|", l, try and())) }
            return l
        }
        mutating func and() throws -> Node {
            var l = try cmp()
            while eatStr("&&") { l = make(.bin("&", l, try cmp())) }
            return l
        }
        mutating func cmp() throws -> Node {
            var l = try add()
            while true {
                if eatStr("<=") { l = make(.bin("l", l, try add())) }
                else if eatStr(">=") { l = make(.bin("g", l, try add())) }
                else if eatStr("==") { l = make(.bin("=", l, try add())) }
                else if eatStr("!=") { l = make(.bin("!", l, try add())) }
                else if peek("<") { i += 1; l = make(.bin("<", l, try add())) }
                else if peek(">") { i += 1; l = make(.bin(">", l, try add())) }
                else { return l }
            }
        }
        mutating func add() throws -> Node {
            var l = try mul()
            while true {
                if eat("+") { l = make(.bin("+", l, try mul())) }
                else if eat("-") { l = make(.bin("-", l, try mul())) }
                else { return l }
            }
        }
        mutating func mul() throws -> Node {
            var l = try unary()
            while true {
                if eat("*") { l = make(.bin("*", l, try unary())) }
                else if eat("/") { l = make(.bin("/", l, try unary())) }
                else if eat("%") { l = make(.bin("%", l, try unary())) }
                else { return l }
            }
        }
        mutating func unary() throws -> Node {
            if eat("-") { return make(.neg(try unary())) }
            if peek("!") , i + 1 < s.count, s[i + 1] != "=" { i += 1; return make(.not(try unary())) }
            return try power()
        }
        mutating func power() throws -> Node {
            let b = try primary()
            if eat("^") { return make(.bin("^", b, try unary())) }
            return b
        }
        mutating func primary() throws -> Node {
            ws()
            guard i < s.count else { throw ParseError.syntax("unexpected end") }
            if eat("(") {
                let n = try ternary()
                guard eat(")") else { throw ParseError.syntax("expected ')'") }
                return n
            }
            if s[i].isNumber || s[i] == "." {
                var t = ""
                while i < s.count, s[i].isNumber || s[i] == "." { t.append(s[i]); i += 1 }
                guard let d = Double(t) else { throw ParseError.syntax("bad number '\(t)'") }
                return make(.num(d))
            }
            if s[i].isLetter || s[i] == "_" {
                var name = ""
                while i < s.count, s[i].isLetter || s[i].isNumber || s[i] == "_" || s[i] == "." { name.append(s[i]); i += 1 }
                if peek("(") {
                    guard let f = Fn(rawValue: name) else { throw ParseError.unknownFunction(name) }
                    i += 1
                    var args: [Node] = []
                    if !eat(")") {
                        repeat { args.append(try ternary()) } while eat(",")
                        guard eat(")") else { throw ParseError.syntax("expected ')'") }
                    }
                    guard f.arity.contains(args.count) else { throw ParseError.wrongArguments(name) }
                    return make(.call(f, args))
                }
                if let c = Self.constants[name] { return make(.num(c)) }
                guard let idx = vars[name] else { throw ParseError.unknownVariable(name) }
                used.insert(idx)
                return make(.v(idx))
            }
            throw ParseError.syntax("unexpected '\(s[i])'")
        }
    }
}
