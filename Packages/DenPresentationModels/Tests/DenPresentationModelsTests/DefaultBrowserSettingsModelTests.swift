import DenDomain
import DenPresentationModels
import Testing

@MainActor
struct DefaultBrowserSettingsModelTests {
    @Test(arguments: [false, true])
    func registrationRefreshesStatusBeforeReportingFailure(accepted: Bool) async {
        var events: [String] = []
        let model = DefaultBrowserSettingsModel(
            destination: { .drawerPeek }, setDestination: { _ in },
            loadStatus: {
                events.append("refresh")
                return accepted ? .denBrowser : .unavailable
            },
            setDefault: { events.append("register") })

        await model.makeDefaultBrowser()

        #expect(events == ["register", "refresh"])
        #expect(!model.isSettingDefault)
        #expect(model.status.isDenBrowser == accepted)
        #expect((model.errorMessage == nil) == accepted)
    }
}
