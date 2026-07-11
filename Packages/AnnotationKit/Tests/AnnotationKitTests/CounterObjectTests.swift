// Packages/AnnotationKit/Tests/AnnotationKitTests/CounterObjectTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("CounterObject")
struct CounterObjectTests {
    @Test("Counter has correct bounds centered on point")
    func bounds() {
        let counter = CounterObject(center: CGPoint(x: 100, y: 200), number: 1)
        let b = counter.bounds
        #expect(b.midX == 100)
        #expect(b.midY == 200)
        #expect(b.width == counter.radius * 2)
        #expect(b.height == counter.radius * 2)
    }

    @Test("Counter hit test inside circle")
    func hitTestInside() {
        let counter = CounterObject(center: CGPoint(x: 100, y: 100), number: 1)
        #expect(counter.hitTest(point: CGPoint(x: 100, y: 100), threshold: 0))
        #expect(counter.hitTest(point: CGPoint(x: 100 + counter.radius - 1, y: 100), threshold: 0))
    }

    @Test("Counter hit test outside circle")
    func hitTestOutside() {
        let counter = CounterObject(center: CGPoint(x: 100, y: 100), number: 1)
        #expect(!counter.hitTest(point: CGPoint(x: 200, y: 200), threshold: 0))
    }

    @Test("Counter hit test with threshold")
    func hitTestThreshold() {
        let counter = CounterObject(center: CGPoint(x: 100, y: 100), number: 1)
        let justOutside = CGPoint(x: 100 + counter.radius + 2, y: 100)
        #expect(!counter.hitTest(point: justOutside, threshold: 0))
        #expect(counter.hitTest(point: justOutside, threshold: 5))
    }

    @Test("Counter move updates center")
    func move() {
        let counter = CounterObject(center: CGPoint(x: 50, y: 50), number: 3)
        counter.move(by: CGSize(width: 10, height: -5))
        #expect(counter.center.x == 60)
        #expect(counter.center.y == 45)
    }

    @Test("Counter copy preserves number and center")
    func copy() {
        let original = CounterObject(center: CGPoint(x: 75, y: 80), number: 5, style: StrokeStyle(color: .blue))
        let copied = original.copy()
        guard let counterCopy = copied as? CounterObject else {
            Issue.record("copy() did not return CounterObject")
            return
        }
        #expect(counterCopy.center == original.center)
        #expect(counterCopy.number == original.number)
        #expect(counterCopy.radius == original.radius)
        #expect(counterCopy.style.color == .blue)
        #expect(counterCopy.id != original.id)
    }

    @Test("Counter stores its number")
    func number() {
        let c1 = CounterObject(center: .zero, number: 1)
        let c2 = CounterObject(center: .zero, number: 42)
        #expect(c1.number == 1)
        #expect(c2.number == 42)
    }
}
