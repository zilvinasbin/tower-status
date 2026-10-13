import Foundation
import Testing
@testable import TowerCore

private func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "dash", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private let generated = TowerDate.parse("2026-10-13T13:53:40.120Z")!
private let utc = TimeZone(identifier: "UTC")!

private func snapshot(
    occupied: Int? = 1, allocated: Int? = 3, needsYou: Int = 0, schema: Int? = 2,
    generatedAt: Date? = generated, host: DashSnapshot.Host = .init()
) -> DashSnapshot {
    DashSnapshot(schema: schema, generatedAt: generatedAt,
                 slots: .init(allocated: allocated, occupied: occupied),
                 needsYou: Array(repeating: .init(kind: "blocked", project: "vt"), count: needsYou),
                 host: host)
}

private func present(_ outcomes: [FetchOutcome], at now: Date = generated.addingTimeInterval(5),
                     hasAddress: Bool = true) -> Presentation {
    var state = PollState(hasAddress: hasAddress)
    for o in outcomes { state = state.applying(o, at: now) }
    return Presentation(state: state, now: now, timeZone: utc)
}

// MARK: - Section 3: decoding

@Suite struct DecodingTests {
    @Test func decodesFixture() throws {
        let s = try DashSnapshot.decode(fixture())
        #expect(s.schema == 2)
        #expect(s.generatedAt == generated)
        #expect(s.slots.occupied == 4)
        #expect(s.slots.allocated == 3)
        #expect(s.agents.count == 2)
        #expect(s.agents[0].url == URL(string: "https://tracker.example/VT-12"))
        #expect(s.agents[1].startedAt == TowerDate.parse("2026-10-13T11:50:40Z"))
        #expect(s.needsYou.count == 2)
        #expect(s.needsYou[1].since == nil)
        #expect(s.projects.count == 3)
        #expect(s.warnings == [])
    }

    @Test func bytesBeyond2to53DecodeExactly() throws {
        let s = try DashSnapshot.decode(fixture())
        #expect(s.host.memTotalBytes == UInt64.max)
        #expect(s.host.memUsedBytes == 18446744073709551000)
        #expect(s.host.cpuPercent == nil)
    }

    @Test func emptyObjectDecodesWithDefaults() throws {
        let s = try DashSnapshot.decode(Data("{}".utf8))
        #expect(s.schema == nil)
        #expect(s.agents == [])
        #expect(s.slots == .init())
        #expect(s.host == .init())
    }

    @Test func wrongTypesAndBadElementsAreDropped() throws {
        let json = #"{"schema":"two","slots":{"allocated":"3","occupied":1},"agents":[1,{"project":"vt"}],"warnings":["a",2,"b"],"host":null}"#
        let s = try DashSnapshot.decode(Data(json.utf8))
        #expect(s.schema == nil)
        #expect(s.slots.allocated == nil)
        #expect(s.slots.occupied == 1)
        #expect(s.agents.map(\.project) == ["vt"])
        #expect(s.warnings == ["a", "b"])
    }

    @Test func classifiesResponses() throws {
        #expect(TowerClient.classify(status: 200, body: try fixture()) == .snapshot(try DashSnapshot.decode(fixture())))
        #expect(TowerClient.classify(status: 200, body: Data("<html>".utf8)) == .unreadable)
        #expect(TowerClient.classify(status: 200, body: Data("[]".utf8)) == .unreadable)
        #expect(TowerClient.classify(status: 503, body: Data(#"{"error":"snapshot unavailable"}"#.utf8)) == .unavailable)
        #expect(TowerClient.classify(status: 421, body: Data()) == .misdirected)
        #expect(TowerClient.classify(status: 404, body: Data()) == .httpStatus(404))
    }
}

// MARK: - Address setting

@Suite struct AddressTests {
    @Test func addsDefaultPort() {
        #expect(TowerAddress("100.64.0.7")?.feedURL.absoluteString == "http://100.64.0.7:8090/dash.json")
        #expect(TowerAddress(" 100.64.0.7:9000 ")?.dashboardURL.absoluteString == "http://100.64.0.7:9000/")
    }

    @Test func acceptsPastedURL() {
        #expect(TowerAddress("http://100.64.0.7:8090/dash.json")?.authority == "100.64.0.7:8090")
    }

    @Test func ipv6() {
        #expect(TowerAddress("fd7a:115c::1")?.authority == "[fd7a:115c::1]:8090")
        #expect(TowerAddress("[fd7a:115c::1]:81")?.authority == "[fd7a:115c::1]:81")
    }

    @Test func rejectsGarbage() {
        #expect(TowerAddress("") == nil)
        #expect(TowerAddress("   ") == nil)
        #expect(TowerAddress("100.64.0.7:port") == nil)
        #expect(TowerAddress("a b") == nil)
    }
}

// MARK: - Section 4: display rules

@Suite struct DisplayRuleTests {
    let now = generated.addingTimeInterval(5)

    func lines(_ s: DashSnapshot) -> Presentation.DataLines {
        Presentation.dataLines(for: s, now: now)
    }

    @Test func slots() {
        #expect(lines(snapshot(occupied: 1, allocated: 3)).slots == .init("Slots: 1/3"))
    }

    @Test func needsYou() {
        #expect(lines(snapshot(needsYou: 5)).needsYou.text == "Needs you: 5")
        #expect(lines(snapshot(needsYou: 5)).needsYouCount == 5)
    }

    @Test func queueSumsReadyOfEnabledProjects() throws {
        let s = try DashSnapshot.decode(fixture())
        #expect(lines(s).queue.text == "Queue: 3")
    }

    @Test func hostMem() {
        let h = DashSnapshot.Host(memUsedBytes: 32, memTotalBytes: 100)
        #expect(lines(snapshot(host: h)).host.text.contains("MEM 32%"))
    }

    @Test func hostDiskIsUsedShare() {
        let h = DashSnapshot.Host(diskFreeBytes: 43384242176, diskTotalBytes: 105467994112)
        #expect(lines(snapshot(host: h)).host.text.contains("DISK 59%"))
    }

    @Test func hostCpuRounded() {
        let h = DashSnapshot.Host(cpuPercent: 31.4)
        #expect(lines(snapshot(host: h)).host.text.contains("CPU 31%"))
    }

    @Test func hostFullLine() {
        let h = DashSnapshot.Host(diskFreeBytes: 41, diskTotalBytes: 100, cpuPercent: 31.4, memUsedBytes: 32, memTotalBytes: 100)
        #expect(lines(snapshot(host: h)).host == .init("Host: MEM 32% · DISK 59% · CPU 31%"))
    }

    @Test func agentLine() throws {
        let s = try DashSnapshot.decode(fixture())
        let agents = Presentation.dataLines(for: s, now: generated).agents
        #expect(agents[0] == .init("vt · validate #2 · working · 12m", url: URL(string: "https://tracker.example/VT-12")))
    }

    @Test func nullFiguresShowDash() {
        let l = lines(snapshot(occupied: nil, allocated: nil))
        #expect(l.slots.text == "Slots: –/–")
        #expect(l.host.text == "Host: MEM – · DISK – · CPU –")
        #expect(l.host.tone == .normal)
    }

    @Test func warningLimits() {
        let hot = DashSnapshot.Host(diskFreeBytes: 9, diskTotalBytes: 100, cpuPercent: 90.5, memUsedBytes: 91, memTotalBytes: 100)
        let l = lines(snapshot(host: hot))
        #expect(l.host == .init("Host: MEM 91% ⚠ · DISK 91% ⚠ · CPU 91% ⚠", tone: .warning))

        let atLimit = DashSnapshot.Host(diskFreeBytes: 10, diskTotalBytes: 100, cpuPercent: 90, memUsedBytes: 90, memTotalBytes: 100)
        #expect(lines(snapshot(host: atLimit)).host.tone == .normal)
    }

    @Test func overbookedSlotsWarn() {
        #expect(lines(snapshot(occupied: 4, allocated: 3)).slots == .init("Slots: 4/3 ⚠", tone: .warning))
    }

    @Test func awaitingAgentShowsWaitingForYou() throws {
        let s = try DashSnapshot.decode(fixture())
        let agent = Presentation.dataLines(for: s, now: generated).agents[1]
        #expect(agent.text == "rs · code #1 · waiting for you · 2h 3m")
        #expect(agent.tone == .warning)
    }

    @Test func needsYouRows() throws {
        let s = try DashSnapshot.decode(fixture())
        let rows = Presentation.dataLines(for: s, now: generated).needsYouRows.map(\.text)
        #expect(rows == ["vt · review handoff · 6 risks, 3 left · 7h 49m", "vt · notes to approve · 2 notes · –"])
        #expect(Presentation.needsYouLabel("awaiting_input") == "waits for input")
        #expect(Presentation.needsYouLabel("blocked") == "blocked")
    }

    @Test func warningsPassThrough() {
        var s = snapshot()
        s.warnings = ["host stale"]
        #expect(lines(s).warnings == ["host stale"])
        #expect(lines(snapshot()).warnings == [])
    }

    @Test func titleNormal() {
        let p = present([.snapshot(snapshot(needsYou: 0))])
        #expect(p.title == "T 1/3")
        #expect(!p.titleDimmed)
        #expect(p.messages == [])
    }

    @Test func titleWithNeedsYou() {
        #expect(present([.snapshot(snapshot(needsYou: 5))]).title == "T 1/3 · ⚠5")
    }

    @Test func ages() {
        let t = Date(timeIntervalSince1970: 0)
        #expect(Presentation.age(since: t, now: t.addingTimeInterval(45)) == "45s")
        #expect(Presentation.age(since: t, now: t.addingTimeInterval(720)) == "12m")
        #expect(Presentation.age(since: t, now: t.addingTimeInterval(7200)) == "2h")
        #expect(Presentation.age(since: t, now: t.addingTimeInterval(3 * 86400)) == "3d")
        #expect(Presentation.age(since: t.addingTimeInterval(10), now: t) == "0s")
    }
}

// MARK: - Section 5: states and errors

@Suite struct StateTests {
    @Test func ok200Schema2ShowsData() {
        let p = present([.snapshot(snapshot())])
        #expect(p.data != nil)
        #expect(!p.dataDimmed)
        #expect(p.messages.isEmpty)
    }

    @Test func otherSchemaShowsDataAndUpdateHint() {
        let p = present([.snapshot(snapshot(schema: 3))])
        #expect(p.data?.slots.text == "Slots: 1/3")
        #expect(p.messages == ["Tower schema 3: update the app"])
    }

    @Test func unavailableKeepsLastGood() {
        let p = present([.snapshot(snapshot()), .unavailable])
        #expect(p.data?.slots.text == "Slots: 1/3")
        #expect(p.messages == ["Tower: snapshot unavailable"])
        #expect(p.title == "T 1/3")
    }

    @Test func misdirected421() {
        let p = present([.misdirected])
        #expect(p.messages == ["Use the IP address, not a host name"])
        #expect(p.title == "T –")
        #expect(p.titleDimmed)
    }

    @Test func offlineDimsLastGoodWithTime() {
        var state = PollState(hasAddress: true)
        state = state.applying(.snapshot(snapshot()), at: generated)
        let first = generated.addingTimeInterval(10)  // 13:53:50 UTC
        state = state.applying(.offline, at: first)
        state = state.applying(.offline, at: first.addingTimeInterval(10))
        let p = Presentation(state: state, now: first.addingTimeInterval(10), timeZone: utc)
        #expect(p.messages == ["offline since 13:53"])
        #expect(p.data?.slots.text == "Slots: 1/3")
        #expect(p.dataDimmed)
        #expect(p.title == "T –")
        #expect(p.titleDimmed)
    }

    @Test func staleAfter60Seconds() {
        let fresh = present([.snapshot(snapshot())], at: generated.addingTimeInterval(60))
        #expect(fresh.messages.isEmpty)
        let stale = present([.snapshot(snapshot())], at: generated.addingTimeInterval(61))
        #expect(stale.messages == ["stale"])
        #expect(stale.title == "T –")
        #expect(stale.titleDimmed)
        #expect(stale.dataDimmed)
    }

    @Test func noAddress() {
        let p = present([], hasAddress: false)
        #expect(p.messages == ["Set the Tower address in Settings"])
        #expect(p.title == "T –")
        #expect(p.data == nil)
    }

    @Test func recoversAfterOffline() {
        let p = present([.offline, .snapshot(snapshot())])
        #expect(p.messages.isEmpty)
        #expect(!p.titleDimmed)
    }
}
