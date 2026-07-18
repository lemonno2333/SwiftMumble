import Testing
@testable import SwiftMumbleApp

@Test func serverSessionSelectionSeparatesBrowsingFromActiveSession() {
    var selection = ServerSessionSelection<String>(selectedID: "a")

    let selectedB = selection.select("b")
    #expect(selectedB)
    #expect(selection.selectedID == "b")
    let selectionChangedAtSessionStart = selection.beginSession(serverID: "b")
    #expect(!selectionChangedAtSessionStart)
    #expect(selection.activeID == "b")

    let selectedAWhileActive = selection.select("a")
    #expect(!selectedAWhileActive)
    #expect(selection.selectedID == "b")
    #expect(selection.activeID == "b")

    selection.endSession()
    let selectedAAfterSession = selection.select("a")
    #expect(selectedAAfterSession)
    #expect(selection.selectedID == "a")
    #expect(selection.activeID == nil)
}

@Test func serverSessionSelectionCanForceConnectionTarget() {
    var selection = ServerSessionSelection<String>(selectedID: "a", activeID: "a")

    let forcedB = selection.forceSelect("b")
    #expect(forcedB)
    #expect(selection.selectedID == "b")
    #expect(selection.activeID == "a")
    let selectionChangedAtSessionStart = selection.beginSession(serverID: "b")
    #expect(!selectionChangedAtSessionStart)
    #expect(selection.activeID == "b")
}
