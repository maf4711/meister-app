import XCTest
@testable import MeisterKit

final class SyncStateInspectorTests: XCTestCase {
    func testParseEnabledContacts() {
        let sample = """
        {
            AccountID = "foellmer@mac.com";
            Services = (
                {
                    Enabled = 1;
                    Name = CONTACTS;
                },
                {
                    Enabled = 1;
                    Name = CALENDAR;
                }
            );
        }
        """
        let state = SyncStateInspector.parse(sample)
        XCTAssertEqual(state.accountID, "foellmer@mac.com")
        XCTAssertEqual(state.contactsEnabled, true)
    }

    func testParseDisabledContacts() {
        let sample = """
        {
            AccountID = "foellmer@mac.com";
            Services = (
                {
                    Enabled = 0;
                    Name = CONTACTS;
                }
            );
        }
        """
        let state = SyncStateInspector.parse(sample)
        XCTAssertEqual(state.contactsEnabled, false)
    }

    func testParseMissingContactsService() {
        let sample = """
        {
            AccountID = "someone@icloud.com";
            Services = (
                {
                    Enabled = 1;
                    Name = MAIL;
                }
            );
        }
        """
        let state = SyncStateInspector.parse(sample)
        XCTAssertNil(state.contactsEnabled)
        XCTAssertEqual(state.accountID, "someone@icloud.com")
    }
}
