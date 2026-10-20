import AudioToolbox
import SwiftUI
import SurveyCore
import UIKit

#if !SURVEY_PLAYGROUND && canImport(UserNotifications)
import UserNotifications
#endif

/// SOS の音。Critical Alerts の資格はこの版に無い。実機のマナーモード解除は未確認。
enum SOSSound {
    private static var armed = false

    static func arm() {
        guard !armed else { return }
        armed = true
        #if !SURVEY_PLAYGROUND && canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .criticalAlert]) { _, _ in }
        #endif
    }

    static func ring(_ text: String) {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(1005)
        #if !SURVEY_PLAYGROUND && canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "SOS"
        content.body = text
        content.interruptionLevel = .critical
        content.sound = .defaultCritical
        let request = UNNotificationRequest(identifier: "sos-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        #else
        _ = text
        #endif
    }
}

struct SOSControl: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SOSCall.disclaimer)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(SOSCall.disclaimer)
            if let pointer = field.sosPointer {
                Text(pointer.text)
                    .font(.system(size: 30, weight: .black))
                    .minimumScaleFactor(0.45)
                    .lineLimit(2)
                    .foregroundStyle(Color.white)
                    .accessibilityLabel(pointer.text)
                Button("向かう") {
                    field.respondSOS()
                }
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SurveyColor.amber)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("向かう。SOSを出した人に返す")
            }
            if field.sosActive, !field.sosHelpers.isEmpty {
                Text(field.sosHelpers)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Color.white)
            }
            SOSSlide(active: field.sosActive) {
                field.toggleSOS()
            }
            Button("iPhoneの緊急SOS") {
                field.showsEmergencySOS = true
            }
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.white.opacity(0.9))
            .accessibilityLabel("iPhoneの緊急SOSを開く")
        }
        .padding(12)
        .background(SurveyColor.red)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { SOSSound.arm() }
        .sheet(isPresented: $field.showsEmergencySOS) {
            EmergencySOSSheet()
        }
    }
}

struct SOSSlide: View {
    var active: Bool
    var onCommit: () -> Void
    @State private var offset: CGFloat = 0
    @State private var lockedUntil = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - 76, 1)
            ZStack(alignment: .leading) {
                Text(active ? "スライドか長押しで止める" : "スライドか長押しで SOS")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 68, height: 52)
                    .overlay(Text("SOS").font(.system(size: 16, weight: .black)).foregroundStyle(SurveyColor.red))
                    .offset(x: offset)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                offset = min(max(0, value.translation.width), travel)
                            }
                            .onEnded { value in
                                if value.translation.width > travel * 0.82 {
                                    commit()
                                }
                                offset = 0
                            }
                    )
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.2) {
                commit()
            }
        }
        .frame(height: 56)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(active ? "SOSを止める。スライドか長押し" : "SOSを送る。スライドか長押し")
    }

    private func commit() {
        let now = Date()
        guard now > lockedUntil else { return }
        lockedUntil = now.addingTimeInterval(1.2)
        offset = 0
        onCommit()
    }
}

struct EmergencySOSSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(SOSCall.disclaimer)
                    .font(.system(size: 22, weight: .black))
                    .fixedSize(horizontal: false, vertical: true)
                Text(SOSCall.emergencyHint)
                    .font(.system(size: 18, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(SOSCall.criticalAlertNote)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("119に電話する") {
                    guard let url = URL(string: "tel:119") else { return }
                    UIApplication.shared.open(url)
                }
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(SurveyColor.red)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("119に電話する")
                Spacer()
            }
            .padding(20)
            .background(SurveyColor.background)
            .navigationTitle("緊急SOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SOSRim: View {
    var pointer: SOSPointer?

    var body: some View {
        if let pointer, pointer.known, let degrees = pointer.relativeDegrees {
            GeometryReader { geo in
                let point = rim(degrees, in: geo.size)
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 72, weight: .black))
                        .rotationEffect(.degrees(degrees))
                    Text(pointer.text)
                        .font(.system(size: 26, weight: .black))
                        .minimumScaleFactor(0.45)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.white)
                .padding(12)
                .background(SurveyColor.red)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .position(point)
                .accessibilityLabel(pointer.text)
            }
            .allowsHitTesting(false)
        }
    }

    private func rim(_ degrees: Double, in size: CGSize) -> CGPoint {
        let turn = degrees * .pi / 180
        let inset = min(size.width, size.height) * 0.24
        return CGPoint(
            x: size.width / 2 + CGFloat(sin(turn)) * (size.width / 2 - inset),
            y: size.height / 2 - CGFloat(cos(turn)) * (size.height / 2 - inset)
        )
    }
}
