import Testing

@Suite("Basic")
struct BasicTests {
    @Test("True is true")
    func trueIsTrue() {
        #expect(true)
    }
}
