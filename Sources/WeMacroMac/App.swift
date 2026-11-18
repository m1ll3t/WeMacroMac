// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t

import SwiftUI
import AppKit

@main struct WeMacroApp: App {
    @StateObject private var model = RailModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("WeMacro") {
            ContentView(m: model, link: model.link)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in delegate.keyboard.release() }
                .onAppear { delegate.model = model; delegate.keyboard.install(model: model); NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width:630,height:822).windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
        .commands {
            CommandGroup(after:.appInfo) {
                Button("停止"){model.stop()}.keyboardShortcut(.escape,modifiers:[])
                Button("载入参数…"){model.load()}.disabled(model.busy)
                Button("保存参数…"){model.save()}
                Button("试拍快门"){model.shutter()}.disabled(!model.link.connected || model.busy)
                Button("校准回差"){model.calibrate()}.disabled(!model.link.connected || model.busy)
                Button("导出通信日志…"){model.exportLog()}
                Button("模拟连接"){if !model.link.connected && !model.busy {model.kind="模拟";model.scan()}}
            }
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RailModel?
    let keyboard = RailKeyboard()
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification){model?.stop();model?.link.disconnect()}
}
@MainActor final class RailViewState: ObservableObject {
    @Published var panel: String?
    @Published var held: Int?
    @Published var holdPressActive = false
    @Published var holdOwnsMovement = false
    @Published var autoConnectTipVisible = false
    @Published var autoConnectTipHovered = false
    @Published var autoConnectTipGeneration = UUID()
}
struct ContentView: View {
    @ObservedObject var m:RailModel
    @ObservedObject var link:RailTransport
    @StateObject private var ui=RailViewState()
    @StateObject private var calculator=CalculatorModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private var deviceName:String {m.selected == "demo" ? "测试假设备（模拟）" : (link.devices.first(where:{$0.id==m.selected})?.name ?? m.selected)}
    var body:some View {
        ZStack(alignment:.top) {
            VStack(spacing:0) {
                HStack(spacing:10) {
                    WindowTrafficLightsAlignment().frame(width:90,height:59)
                    Text("WeMacro").font(.system(size:16,weight:.semibold)).allowsHitTesting(false)
                    Text("1.1").font(.system(size:12)).padding(.horizontal,7).padding(.vertical,3).background(Color.black.opacity(0.05),in:RoundedRectangle(cornerRadius:5)).allowsHitTesting(false)
                    Spacer()
                }.frame(height:59).background(WindowDragRegion()).background(.white.opacity(0.5))
                Divider()
                VStack(spacing:17) {
                    connection.frame(height:58)
                    positioning.frame(height:278)
                    endpoints.frame(height:130)
                    capture.frame(height:218)
                }.padding(28)
            }
            .disabled(ui.panel != nil).accessibilityHidden(ui.panel != nil)
            .overlay(alignment:.top) {
              GeometryReader { bounds in
                ZStack(alignment:.top) {
              if let panel=ui.panel {
                Color.black.opacity(0.20).contentShape(Rectangle()).onTapGesture {NSApp.keyWindow?.makeFirstResponder(nil)}.transition(.opacity)
                Group {
                    if panel=="calculator" { CalculatorSheet(model:calculator,close:closePanel,apply:applyStep,canApply:!m.busy) }
                    else { settingsSheet }
                }.frame(width:472).background(RailPalette.background,in:UnevenRoundedRectangle(topLeadingRadius:0,bottomLeadingRadius:14,bottomTrailingRadius:14,topTrailingRadius:0)).overlay(UnevenRoundedRectangle(topLeadingRadius:0,bottomLeadingRadius:14,bottomTrailingRadius:14,topTrailingRadius:0).stroke(Color.black.opacity(0.08))).compositingGroup().shadow(color:.black.opacity(0.16),radius:20,y:14)
                .transition(.opacity)
                .zIndex(1)
              }
            }
            .frame(width:bounds.size.width,height:max(0,bounds.size.height-59),alignment:.top)
            .clipped()
            .animation(reduceMotion ? nil : .timingCurve(0.23,1,0.32,1,duration:0.5),value:ui.panel)
            .allowsHitTesting(ui.panel != nil)
            .padding(.top,59)
              }
            }
        }.overlay(alignment:.topLeading) {
            if ui.panel == "settings", ui.autoConnectTipVisible {
                Text("程序启动后自动搜索并连接设备")
                    .font(.system(size:12))
                    .foregroundStyle(.primary)
                    .padding(.horizontal,10)
                    .padding(.vertical,7)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:7))
                    .overlay(RoundedRectangle(cornerRadius:7).stroke(Color.black.opacity(0.12)))
                    .shadow(color:.black.opacity(0.16),radius:6,y:3)
                    .fixedSize()
                    .offset(x:96,y:112)
                    .allowsHitTesting(false)
                    .zIndex(1000)
                    .transition(.opacity)
            }
        }
        .frame(width:630,height:822,alignment:.top).ignoresSafeArea(.container,edges:.top)
        .background(RailPalette.background).preferredColorScheme(.light).font(.system(size:14))
        .buttonStyle(PressedOverlayStyle(bordered:true))
        .environment(\.railButtonAction, {m.resetCaptureCompletion()})
        .onChange(of:m.settings){m.resetCaptureCompletion();m.saveDefaults()}
        .onChange(of:ui.panel){m.controlsBlocked = ui.panel != nil}
        .onChange(of:m.calculatorRequest){openPanel("calculator")}
        .onChange(of:link.devices){_,devices in
            if m.selected != "demo", !devices.contains(where:{$0.id==m.selected}) {m.selected=devices.first(where:{$0.name.localizedCaseInsensitiveContains("HC-08") || $0.name.localizedCaseInsensitiveContains("wemacro")})?.id ?? devices.first?.id ?? ""}
        }
        .alert("提示",isPresented:Binding(get:{m.error != nil},set:{if !$0 {m.error=nil}})){Button("好"){m.error=nil}} message:{Text(m.error ?? "")}
    }
    func openPanel(_ name:String){
        guard !m.busy || (name == "calculator" && m.capturing) else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        if !m.capturing { m.endStepHold(); m.endHold() }
        ui.panel=name
    }
    func closePanel(){
        NSApp.keyWindow?.makeFirstResponder(nil)
        if ui.panel == "settings" {
            do { try m.settings.validate() }
            catch { m.error = error.localizedDescription; return }
        }
        ui.panel=nil
    }
    func validateTime(_ value:Double,title:String){
        guard value.isFinite, (0.01...99).contains(value) else {
            m.error = "\(title)须在 0.01–99 秒之间"
            return
        }
    }
    func applyStep(_ microns:Double){guard !m.busy else{return};let useMicrons=microns<=1000;let value=useMicrons ? floor(microns):floor(microns/100)/10;m.settings.microns=useMicrons;m.settings.step=value;let defaults=UserDefaults.standard;defaults.set(value,forKey:useMicrons ? "step.memory.microns":"step.memory.millimeters");defaults.removeObject(forKey:useMicrons ? "step.memory.millimeters":"step.memory.microns");m.saveDefaults();closePanel()}
    var connection:some View {
        RailCard {
            HStack(spacing:10) {
                HStack(spacing:0){ForEach(["USB","蓝牙"],id:\.self){kind in
                    Button{m.kind=kind;m.scan()} label:{Text(kind).fontWeight(m.kind==kind ? .semibold:.regular).frame(width:68,height:26).background{if m.kind==kind {RoundedRectangle(cornerRadius:6).fill(.white).shadow(color:.black.opacity(0.16),radius:1,y:1)}}}.buttonStyle(PressedOverlayStyle())
                }}.padding(3).background(Color.black.opacity(0.055),in:RoundedRectangle(cornerRadius:8)).disabled(link.connected).allowsHitTesting(!m.busy)
                Picker("设备",selection:$m.selected){Text("选择设备").tag("");ForEach(link.devices.filter{$0.id != "demo"}){Text($0.name).tag($0.id)};Text("测试假设备（模拟移动）").tag("demo")}.labelsHidden().frame(maxWidth:.infinity).disabled(link.connected).allowsHitTesting(!m.busy)
                Button{m.scan()}label:{Image(systemName:"arrow.clockwise").frame(width:15,height:16)}.help("重新扫描").disabled(link.connected).allowsHitTesting(!m.busy)
                Button{m.toggleConnection()}label:{
                    Text(link.connected ? "断开":"连接")
                        .foregroundStyle(link.connected ? Color.primary:Color.white)
                        .padding(.horizontal,10).padding(.vertical,5)
                        .background(link.connected ? Color.white:Color.blue,in:RoundedRectangle(cornerRadius:6))
                        .overlay(RoundedRectangle(cornerRadius:6).stroke(link.connected ? Color.black.opacity(0.18):Color.clear).allowsHitTesting(false))
                }.buttonStyle(PressedOverlayStyle()).disabled(!link.connected && m.selected.isEmpty).allowsHitTesting(!m.busy)
            }.padding(.horizontal,18).frame(maxHeight:.infinity)
        }
    }
    var positioning:some View {
        RailCard {
            VStack(spacing:0) {
                HStack(spacing:10) {
                    Circle().fill(link.connected ? .green:.gray).frame(width:11,height:11)
                    Text(link.connected ? "已连接 · \(deviceName)":link.status).font(.system(size:17,weight:.semibold)).lineLimit(1)
                    Spacer(minLength:0)
                    Button{openPanel("settings")}label:{Image(systemName:"gearshape").frame(width:15,height:16)}.help("设置")
                    Button{openPanel("calculator")}label:{Label {Text("步长计算器")} icon:{CalculatorIcon()}.labelStyle(.titleAndIcon).foregroundStyle(.white).frame(height:16).padding(.horizontal,10).padding(.vertical,5).background(.blue,in:RoundedRectangle(cornerRadius:6))}.buttonStyle(PressedOverlayStyle())
                }.padding(.bottom,28)
                HStack {
                    Text("步长设置").fontWeight(.semibold);Spacer()
                    RailNumber(title:"步长",value:stepBinding,suffix:m.settings.microns ? "µm":"mm",width:120,precision:m.settings.microns ? 0:1,rounding:.down).allowsHitTesting(!m.busy)
                    HStack(spacing:0){unitButton("mm",microns:false);unitButton("µm",microns:true)}.padding(3).background(Color.black.opacity(0.055),in:RoundedRectangle(cornerRadius:7))
                }.padding(.bottom,28)
                HStack(spacing:9) {
                    moveButton("后退 10 步",direction:-1,large:true)
                    moveButton("后退 1 步",direction:-1,large:false)
                    moveButton("前进 1 步",direction:1,large:false)
                    moveButton("前进 10 步",direction:1,large:true)
                }.padding(.bottom,10)
                HStack(spacing:10){holdControl(-1);holdControl(1)}
            }.padding(23).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    func unitButton(_ label:String,microns:Bool)->some View {
        Button{switchStepUnit(to:microns)}label:{Text(label).fontWeight(m.settings.microns==microns ? .semibold:.regular).frame(width:47,height:26).background{if m.settings.microns==microns {RoundedRectangle(cornerRadius:5).fill(.white).shadow(color:.black.opacity(0.14),radius:1,y:1)}}}.buttonStyle(PressedOverlayStyle())
    }
    private var stepBinding:Binding<Double>{Binding(get:{m.settings.step},set:{value in
        m.settings.step=value
        let defaults=UserDefaults.standard
        let currentKey=m.settings.microns ? "step.memory.microns":"step.memory.millimeters"
        let otherKey=m.settings.microns ? "step.memory.millimeters":"step.memory.microns"
        defaults.set(value,forKey:currentKey);defaults.removeObject(forKey:otherKey)
    })}
    private func switchStepUnit(to microns:Bool){
        guard !m.busy else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard m.settings.microns != microns else{return}
        let defaults=UserDefaults.standard
        let sourceKey=m.settings.microns ? "step.memory.microns":"step.memory.millimeters"
        let targetKey=microns ? "step.memory.microns":"step.memory.millimeters"
        defaults.set(m.settings.step,forKey:sourceKey)
        let converted=microns ? m.settings.step*1000:m.settings.step/1000
        let value:Double
        if defaults.object(forKey:targetKey) != nil, let remembered=defaults.object(forKey:targetKey) as? Double {
            value=remembered
        } else {
            value=microns ? floor(converted):floor(converted*10)/10
        }
        m.settings.microns=microns;m.settings.step=value
        defaults.set(value,forKey:targetKey)
    }
    func moveButton(_ title:String,direction:Int,large:Bool)->some View {
        let distance=m.settings.roundedStep*Double(large ? 10:1)
        return Button{NSApp.keyWindow?.makeFirstResponder(nil);m.jog(direction,large:large)}label:{
            VStack(spacing:3){Text(title).font(.system(size:12)).foregroundStyle(.secondary);HStack(alignment:.firstTextBaseline,spacing:3){Text(distance.formatted(.number.precision(.fractionLength(0...3)))).font(.system(size:16,weight:.semibold));Text(m.settings.microns ? "µm":"mm").font(.system(size:12)).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity).frame(height:57)
        }.buttonStyle(PressedOverlayStyle(bordered:true,cornerRadius:10,dimDisabled:!link.connected)).disabled(!link.connected)
    }
    func holdControl(_ direction:Int)->some View {
        HStack(spacing:5){if direction<0 {Image(systemName:"backward.fill")};Text(direction<0 ? "快退":"快进").fontWeight(.semibold);Text("按住").foregroundStyle(.secondary);if direction>0 {Image(systemName:"forward.fill")}}
            .frame(maxWidth:.infinity).frame(height:48)
            .background(Color.black.opacity(ui.held==direction ? 0.20:0.035),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(Color.black.opacity(0.18)).allowsHitTesting(false))
            .opacity(link.connected ? 1:0.45).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged{_ in
                guard !ui.holdPressActive, link.connected, ui.panel==nil else { return }
                ui.holdPressActive=true;ui.held=direction;ui.holdOwnsMovement=false
                NSApp.keyWindow?.makeFirstResponder(nil)
                // Decide once at press-down: an ignored press never starts later when busy clears.
                guard !m.busy else { return }
                m.beginHold(direction);ui.holdOwnsMovement=m.holding
            }.onEnded{_ in releaseMouseHold()})
            .accessibilityAddTraits(.isButton).accessibilityLabel(direction<0 ? "按住快速后退":"按住快速前进").onDisappear{if ui.held==direction {releaseMouseHold()}}
    }
    private func releaseMouseHold(){
        if ui.holdOwnsMovement {m.endHold()}
        ui.held=nil;ui.holdPressActive=false;ui.holdOwnsMovement=false
    }
    var endpoints:some View {
        RailCard {HStack(spacing:14){endpoint("起点",value:m.start,color:.green,mark:m.markStart);endpoint("终点",value:m.end,color:.red,mark:m.markEnd)}.padding(18).frame(maxHeight:.infinity)}
    }
    func endpoint(_ title:String,value:Int?,color:Color,mark:@escaping ()->Void)->some View {
        VStack(spacing:15) {
            HStack(spacing:6){Circle().fill(color).frame(width:9,height:9);Text(title).foregroundStyle(color).fontWeight(.semibold);Spacer();Text(title == "终点" && m.start == nil && value != nil ? "终点已设置" : value.map{String(format:"%.3f mm",Double($0)/6400)} ?? "—").monospacedDigit()}
            HStack(spacing:8){Button(action:mark){Text("设为\(title)").frame(maxWidth:.infinity)};Button("前往"){m.go(value)}.disabled(value==nil)}.disabled(!link.connected)
        }.padding(16).frame(maxWidth:.infinity).background(RailPalette.background,in:RoundedRectangle(cornerRadius:10))
    }
    var capture:some View {
        RailCard {
            VStack(spacing:0) {
                HStack {
                    (Text("拍摄 · ").foregroundColor(.secondary)+Text(m.captureEndToStart ? "终点":"起点").foregroundColor(m.captureEndToStart ? .red:.green)+Text(" → ").foregroundColor(.secondary)+Text(m.captureEndToStart ? "起点":"终点").foregroundColor(m.captureEndToStart ? .green:.red)).font(.system(size:13,weight:.semibold))
                    Spacer();Button{if !m.busy {m.captureEndToStart.toggle()}}label:{Label("切换",systemImage:"arrow.left.arrow.right")}
                }
                Spacer()
                HStack {
                    stat("总距离",m.hasRange ? String(format:"%.3f mm",m.distance):"—",alignment:.leading)
                    stat("拍摄张数",m.hasRange ? "\(m.frames*m.settings.shutters)":"—",alignment:.center)
                    stat("剩余张数",m.hasRange ? "\(m.remainingShots)":"—",alignment:.trailing)
                }
                Spacer()
                GeometryReader{g in ZStack(alignment:.leading){Capsule().fill(Color.black.opacity(0.10));Capsule().fill(.blue).frame(width:g.size.width*min(1,Double(m.shotsTaken)/Double(max(1,m.frames*m.settings.shutters))))}}.frame(height:6)
                Spacer()
                HStack {
                    if m.busy {
                        Text(!m.capturing ? m.phase:"拍摄中…").foregroundStyle(.secondary).font(.system(size:13)).lineLimit(2)
                    } else {
                        Button{openPanel("settings")}label:{HStack(spacing:3){Text("每步\(m.settings.shutters)张 · 快门间隔\(m.settings.interval.formatted())秒 · 运动后稳定\(m.settings.settling.formatted())秒").lineLimit(1).minimumScaleFactor(0.8);Image(systemName:"chevron.right").fontWeight(.semibold)}}.font(.system(size:12)).foregroundStyle(.secondary).buttonStyle(PressedOverlayStyle())
                    }
                    Spacer(minLength:8)
                    let showingStop = m.busy && m.capturing
                    Button{NSApp.keyWindow?.makeFirstResponder(nil);if showingStop {m.stop()}else if !m.busy && !m.captureFinished {m.run()}}label:{Label(showingStop ? "停止":m.captureFinished ? "已完成":"运行",systemImage:showingStop ? "stop.fill":m.captureFinished ? "checkmark":"camera.fill").font(.system(size:17,weight:.semibold)).foregroundStyle(.white).frame(width:153,height:36).background(showingStop ? Color.red:m.captureFinished ? Color.green:Color.blue,in:RoundedRectangle(cornerRadius:9))}.buttonStyle(PressedOverlayStyle(dimDisabled:!m.canRun && !m.captureFinished,resetsCompletion:false)).disabled(!showingStop && !m.captureFinished && !m.canRun)
                }
            }.padding(23).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    func stat(_ title:String,_ value:String,alignment:HorizontalAlignment)->some View {
        VStack(alignment:alignment,spacing:6){Text(title).font(.system(size:12)).foregroundStyle(.secondary);Text(value).font(.system(size:23,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)}.frame(maxWidth:.infinity,alignment:alignment == .leading ? .leading:alignment == .trailing ? .trailing:.center)
    }
    var settingsSheet:some View {
        VStack(spacing:0) {
            HStack{Text("设置").fontWeight(.semibold);Spacer()}.padding(.horizontal,24).padding(.vertical,20)
            Divider()
            VStack(spacing:17) {
                RailCard {HStack(spacing:6){Text("自动连接");Button{withAnimation(.easeOut(duration:0.08)){ui.autoConnectTipVisible.toggle()}}label:{Image(systemName:"questionmark.circle").foregroundStyle(.secondary).frame(width:20,height:22).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("自动连接说明").accessibilityHint("程序启动后自动搜索并连接设备")
.onContinuousHover { phase in
    let inside: Bool
    switch phase {
    case .active: inside = true
    case .ended: inside = false
    }
    ui.autoConnectTipHovered = inside
    ui.autoConnectTipGeneration = UUID()
    let generation = ui.autoConnectTipGeneration
    if inside {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            guard ui.autoConnectTipHovered, ui.autoConnectTipGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.08)) { ui.autoConnectTipVisible = true }
        }
    } else {
        withAnimation(.easeOut(duration: 0.08)) { ui.autoConnectTipVisible = false }
    }
}
.zIndex(ui.autoConnectTipVisible ? 100:0);Spacer();Toggle("自动连接",isOn:$m.autoConnectEnabled).labelsHidden().toggleStyle(.switch).tint(.green)}.frame(height:50).padding(.horizontal,16)}
                RailCard {VStack(spacing:0){RailRow("每步快门次数"){Text("\(m.settings.shutters)");RailStepper{m.settings.shutters=max(1,m.settings.shutters-1)}plus:{m.settings.shutters=min(9,m.settings.shutters+1)}};Divider().padding(.horizontal,16);RailRow("快门间隔"){RailNumber(title:"快门间隔",value:$m.settings.interval,suffix:"秒",onEditingEnded:{validateTime(m.settings.interval,title:"快门间隔")})};Divider().padding(.horizontal,16);RailRow("运动后稳定"){RailNumber(title:"运动后稳定",value:$m.settings.settling,suffix:"秒",onEditingEnded:{validateTime(m.settings.settling,title:"运动后稳定")})}}}
                RailCard {VStack(spacing:0){RailRow("回差"){RailNumber(title:"回差",value:$m.settings.backlash,suffix:"µm")};Divider().padding(.horizontal,16);RailRow("运行前自动补偿回差"){Toggle("补偿回差",isOn:$m.settings.compensate).labelsHidden().toggleStyle(.switch).tint(.green)}}}
                RailCard {VStack(spacing:0){RailRow("完成后蜂鸣"){Toggle("完成后蜂鸣",isOn:$m.settings.beep).labelsHidden().toggleStyle(.switch).tint(.green)};Divider().padding(.horizontal,16);RailRow("完成后回到起点"){Toggle("完成后回到起点",isOn:$m.settings.returnToStart).labelsHidden().toggleStyle(.switch).tint(.green)}}}
                HStack{Spacer();Button{closePanel()}label:{Text("完成").fontWeight(.semibold).foregroundStyle(.white).frame(width:86,height:32).background(.blue,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(PressedOverlayStyle())}.padding(.top,5)
            }.padding(.horizontal,24).padding(.vertical,20)
        }
    }
}
enum RailPalette {static let background=Color(red:0.965,green:0.965,blue:0.975)}
struct RailCard<C:View>:View {
    @ViewBuilder var content:()->C
    var body:some View {content().background(.white,in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).stroke(Color.black.opacity(0.08)).allowsHitTesting(false))}
}
struct RailRow<C:View>:View {
    let title:String
    let height:CGFloat
    @ViewBuilder var content:()->C
    init(_ title:String,height:CGFloat=50,@ViewBuilder content:@escaping ()->C){self.title=title;self.height=height;self.content=content}
    var body:some View {HStack(spacing:10){Text(title);Spacer(minLength:10);content()}.frame(height:height).padding(.horizontal,16)}
}
struct RailNumber:View {
    let title:String
    @Binding var value:Double
    var suffix:String=""
    var width:CGFloat=120
    var precision:Int=3
    var rounding:FloatingPointRoundingRule = .toNearestOrAwayFromZero
    var onEditingEnded:()->Void = {}
    @FocusState private var focused:Bool
    var body:some View {
        HStack(spacing:4) {
            TextField(title,value:$value,format:.number.rounded(rule:rounding).precision(.fractionLength(0...precision)))
                .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .focused($focused)
                .onSubmit { focused = false }
                .onChange(of:focused) { wasFocused,isFocused in
                    if wasFocused && !isFocused {
                        DispatchQueue.main.async { onEditingEnded() }
                    }
                }
                .frame(maxWidth:.infinity).accessibilityLabel(title)
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(.secondary).fixedSize().allowsHitTesting(false)
            }
        }
        .padding(.horizontal,9).frame(width:width,height:27)
        .background(.white,in:RoundedRectangle(cornerRadius:6))
        .overlay(RoundedRectangle(cornerRadius:6).stroke(Color.black.opacity(0.20)).allowsHitTesting(false))
    }
}
struct RailStepper:View {
    let minus:()->Void
    let plus:()->Void
    var body:some View {HStack(spacing:0){Button{NSApp.keyWindow?.makeFirstResponder(nil);minus()}label:{Image(systemName:"minus").frame(width:29,height:26)};Divider().frame(height:25);Button{NSApp.keyWindow?.makeFirstResponder(nil);plus()}label:{Image(systemName:"plus").frame(width:29,height:26)}}.buttonStyle(PressedOverlayStyle()).overlay(RoundedRectangle(cornerRadius:6).stroke(Color.black.opacity(0.2)).allowsHitTesting(false))}
}

struct CalculatorIcon:View {
    var body:some View {
        VStack(spacing:2) {
            RoundedRectangle(cornerRadius:0.5).frame(height:3)
            HStack(spacing:2) {
                ForEach(0..<3) { _ in
                    VStack(spacing:2) {
                        Rectangle().frame(width:2,height:2)
                        Rectangle().frame(width:2,height:2)
                    }
                }
            }
        }.padding(2).frame(width:12,height:14)
            .overlay(RoundedRectangle(cornerRadius:2).stroke(lineWidth:1.1))
            .accessibilityHidden(true)
    }
}
