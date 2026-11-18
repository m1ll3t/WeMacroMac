import SwiftUI
import AppKit
import DepthCore

@MainActor final class CalculatorModel: ObservableObject {
    @Published var input = DepthInput(na: 0.1, magnification: 5)
    @Published var copied = false
    @Published var basisExpanded = true
    @Published var lens = MacroLens.aksen45 {
        didSet {
            guard lens != oldValue else { return }
            var previous = LensParameters(lens: oldValue)
            previous.input = input; previous.aperture = aperture
            restore(memory.exchange(from: oldValue, parameters: previous, to: lens))
        }
    }
    private var memory = TabMemory()
    private func restore(_ values: LensParameters) {
        let sharedPixelSize = input.pixelSize
        input = values.input
        input.pixelSize = sharedPixelSize
        aperture = values.aperture
        copied = false
        updateNA()
    }
    func resetCurrent() { restore(LensParameters(lens: lens)) }
    @Published var aperture = 2.8
    @Published var cameraBrand = "索尼"
    @Published var cameraID = "索尼:A7R V"
    init() {
        let defaults = UserDefaults.standard
        let savedBrand = defaults.string(forKey: "cameraBrand") ?? "索尼"
        let savedID = defaults.string(forKey: "cameraID") ?? "索尼:A7R V"
        input = LensParameters(lens: .aksen45).input
        aperture = MacroLens.aksen45.apertures[0]
        cameraBrand = savedBrand
        cameraID = savedID
        if savedBrand == "手动输入" {
            input.pixelSize = defaults.double(forKey: "cameraPixelSize") > 0 ? defaults.double(forKey: "cameraPixelSize") : 3.76
        } else if let camera = CameraCatalog.all.first(where: { $0.id == savedID }) {
            input.pixelSize = camera.pixelSize
        } else {
            cameraBrand = "索尼"
            cameraID = "索尼:A7R V"
            input.pixelSize = 3.76
        }
        updateNA()
    }
    func updateBrand() {
        UserDefaults.standard.set(cameraBrand, forKey: "cameraBrand")
        guard cameraBrand != "手动输入" else { cameraID = ""; return }
        let cameras = CameraCatalog.cameras(brand: cameraBrand)
        if !cameras.contains(where: { $0.id == cameraID }) { cameraID = cameras.first?.id ?? "" }
        updateCamera()
    }
    func updateCamera() {
        UserDefaults.standard.set(cameraID, forKey: "cameraID")
        guard let camera = CameraCatalog.all.first(where: { $0.id == cameraID }) else { return }
        input.pixelSize = camera.pixelSize
    }
    func updateNA() {
        let na: Double?
        switch lens {
        case .aksen45, .aksen175:
            na = lens.tableNA(aperture: aperture, magnification: input.magnification)
        case .macro:
            na = lens.estimatedNA(aperture: aperture, magnification: input.magnification)
        case .manual:
            na = nil
        }
        guard let na else { return }
        input.na = na
    }
}
struct CalculatorSheet:View {
    @ObservedObject var model:CalculatorModel
    let close:()->Void
    let apply:(Double)->Void
    var canApply = true
    private var result:DepthResult? {
        if model.lens == .manual && (!(1...50).contains(model.input.magnification) || !(0.01...0.99).contains(model.input.na)){return nil}
        return try? DepthCalculator.calculateForLens(model.input,lens:model.lens,aperture:model.aperture)
    }
    private var parameterError:String {
        if model.lens == .manual && model.input.na>=1 {return "NA值不能大于等于1"}
        if model.lens == .aksen45 && !model.lens.range.contains(model.input.magnification){return "放大倍率请设置为1-5倍"}
        if model.lens == .aksen175 && !model.lens.range.contains(model.input.magnification){return "放大倍率请设置为5-10倍"}
        if model.lens == .manual && !(1...50).contains(model.input.magnification){return "放大倍率请设置为1-50倍"}
        return "请检查参数"
    }
    private var percent:Binding<Double>{Binding(get:{model.input.overlap*100},set:{model.input.overlap=$0/100})}
    var body:some View {
        VStack(spacing:0) {
            VStack(alignment:.leading,spacing:12) {
                Text("步长计算器").fontWeight(.semibold)
                HStack(spacing:0){ForEach(MacroLens.allCases,id:\.self){lens in
                    Button{NSApp.keyWindow?.makeFirstResponder(nil);model.lens=lens}label:{Text(lens == .aksen45 ? "AKSEN 1–5x":lens == .aksen175 ? "AKSEN 5–10x":lens.rawValue).font(.system(size:13,weight:model.lens==lens ? .semibold:.regular)).frame(maxWidth:.infinity).frame(height:29).background{if model.lens==lens {RoundedRectangle(cornerRadius:7).fill(.white).shadow(color:.black.opacity(0.14),radius:1,y:1)}}}.buttonStyle(PressedOverlayStyle())
                }}.padding(3).background(Color.black.opacity(0.055),in:RoundedRectangle(cornerRadius:9))
            }.padding(.horizontal,24).padding(.vertical,18)
            Divider()
            VStack(spacing:0) {
                VStack(spacing:13) {
                cameraCard
                lensCard
                RailCard {RailRow("重叠率") {RailNumber(title:"重叠率",value:percent,suffix:"%",width:88);RailStepper{adjustOverlap(-1)}plus:{adjustOverlap(1)}}}
                resultCard
                }
                Spacer(minLength:0)
                HStack {
                    Button(action:close){Text("返回").frame(width:84,height:32).background(.white,in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(Color.black.opacity(0.20)).allowsHitTesting(false))}.buttonStyle(PressedOverlayStyle())
                    Spacer()
                    Button{NSApp.keyWindow?.makeFirstResponder(nil);if canApply, let r=result, r.stepMicrons>0, r.stepMicrons<=100_000 {apply(r.stepMicrons)}}label:{Text("使用当前步长").fontWeight(.semibold).foregroundStyle(.white).frame(width:124,height:32).background(.blue,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(PressedOverlayStyle()).disabled(result==nil || !canApply)
                }.padding(.top,19)
            }.padding(.horizontal,24).padding(.vertical,18)
        }
        .frame(height:734,alignment:.top)
        .onChange(of:model.cameraBrand){model.updateBrand()}
        .onChange(of:model.cameraID){model.updateCamera()}
        .onChange(of:model.input.pixelSize){UserDefaults.standard.set($0,forKey:"cameraPixelSize")}
        .onChange(of:model.aperture){model.updateNA()}
        .onChange(of:model.input.magnification){model.updateNA()}
    }
    var cameraCard:some View {
        RailCard {VStack(spacing:0){
            RailRow("机身",height:46){
                Picker("品牌",selection:$model.cameraBrand){ForEach(CameraCatalog.brands,id:\.self){Text($0).tag($0)}}.labelsHidden().frame(width:108)
                if model.cameraBrand != "手动输入" {Picker("机型",selection:$model.cameraID){ForEach(CameraCatalog.cameras(brand:model.cameraBrand)){Text($0.model).tag($0.id)}}.labelsHidden().frame(width:157)}
            }
            Divider().padding(.horizontal,16)
            RailRow("像元尺寸",height:46){if model.cameraBrand=="手动输入" {RailNumber(title:"像元尺寸",value:$model.input.pixelSize,suffix:"µm")}else{Text(String(format:"%.2f µm",model.input.pixelSize)).foregroundStyle(.secondary)}}
        }}
    }
    var lensCard:some View {
        RailCard {VStack(spacing:0){
            if model.lens == .manual {
                RailRow("物镜 NA"){RailNumber(title:"物镜 NA",value:$model.input.na,width:88,precision:2);RailStepper{adjustManual(na:true,direction:-1)}plus:{adjustManual(na:true,direction:1)}}
                Divider().padding(.horizontal,16)
                RailRow("实际成像倍率"){RailNumber(title:"倍率",value:$model.input.magnification,suffix:"×",width:88,precision:0);RailStepper{adjustManual(na:false,direction:-1)}plus:{adjustManual(na:false,direction:1)}}
            }else {
                HStack(spacing:8){
                    Text("倍率");Spacer(minLength:0)
                    Text(model.lens == .macro ? "0.1×":String(format:"%.0f×",model.lens.range.lowerBound)).font(.system(size:12)).monospacedDigit().foregroundStyle(.secondary).frame(width:32,alignment:.trailing)
                    BlueSlider(value:$model.input.magnification,range:model.lens == .macro ? 0.1...2:model.lens.range,step:model.lens == .macro ? 0.1:0.5).frame(width:126,height:30)
                    Text(model.lens == .macro ? "2×":String(format:"%.0f×",model.lens.range.upperBound)).font(.system(size:12)).monospacedDigit().foregroundStyle(.secondary).frame(width:32,alignment:.leading)
                    RailNumber(title:"倍率",value:Binding(get:{model.input.magnification},set:{model.input.magnification=($0*10).rounded()/10}),suffix:"×",width:76,precision:1)
                }.frame(height:46).padding(.horizontal,16)
                Divider().padding(.horizontal,16)
                HStack{Text("光圈匹配");Spacer();Button{NSApp.keyWindow?.makeFirstResponder(nil);if let f=model.lens.recommendedAperture(magnification:model.input.magnification,pixelSize:model.input.pixelSize){model.aperture=f;model.updateNA()}}label:{Text("计算合理 F 值").foregroundStyle(.white).padding(.horizontal,10).padding(.vertical,5).background(.blue,in:RoundedRectangle(cornerRadius:6))}.buttonStyle(PressedOverlayStyle())}.frame(height:46).padding(.horizontal,16)
                Divider().padding(.horizontal,16)
                HStack(spacing:12){Text("光圈");Spacer(minLength:0);HStack(spacing:0){ForEach(model.lens.apertures,id:\.self){f in
                    Button{model.aperture=f}label:{Text(String(format:"f/%g",f)).font(.system(size:13,weight:model.aperture==f ? .semibold:.regular)).frame(maxWidth:.infinity).frame(height:26).background{if model.aperture==f{RoundedRectangle(cornerRadius:5).fill(.white).shadow(color:.black.opacity(0.14),radius:1,y:1)}}}.buttonStyle(PressedOverlayStyle())
                }}.padding(3).frame(width:314).background(Color.black.opacity(0.055),in:RoundedRectangle(cornerRadius:7))}.frame(height:46).padding(.horizontal,16)
                Divider().padding(.horizontal,16)
                HStack{Text("物方 NA（近似）");Spacer();Text(String(format:"%.3f",model.input.na)).foregroundStyle(.secondary)}.frame(height:46).padding(.horizontal,16)
            }
        }}
    }
    var resultCard:some View {
        RailCard {VStack(spacing:14){
            if let r=result {
                HStack(spacing:16){metric("景深",value:r.depthMicrons,detail:String(format:"≈ %.3f mm",r.depthMicrons/1000),color:.primary);metric("步长",value:r.stepMicrons,detail:String(format:"重叠 %.0f%%",model.input.overlap*100),color:Color(red:0,green:0.4,blue:0.81))}
                Divider()
                HStack(spacing:10){Text(r.samplingState).font(.system(size:13,weight:.semibold)).foregroundStyle(samplingColor(r)).padding(.horizontal,9).padding(.vertical,5).background(samplingColor(r).opacity(0.12),in:RoundedRectangle(cornerRadius:5));Spacer();Text(r.sampling<2.3 ? "未充分利用镜头分辨率":r.sampling>3.5 ? "无效放大，并不会更清晰":"倍率与镜头分辨率匹配").font(.system(size:13)).foregroundStyle(.secondary)}
            }else{Label(parameterError,systemImage:"exclamationmark.circle").foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:100)}
        }.padding(20)}
    }
    func samplingColor(_ r:DepthResult)->Color{r.sampling<2.3 ? .red:r.sampling<=3.5 ? .green:.blue}
    func metric(_ title:String,value:Double,detail:String,color:Color)->some View {
        let isStep = title == "步长"
        let displayed = isStep ? (value <= 1000 ? floor(value) : floor(value / 100) / 10) : value
        let unit = isStep && value > 1000 ? "mm" : "µm"
        let shown = isStep && value > 1000 ? displayed : displayed
        let precision = isStep ? (value > 1000 ? 1 : 0) : (value >= 100 ? 1 : value >= 10 ? 2 : 3)
        return VStack(alignment:.leading,spacing:7){Text(title).font(.system(size:13,weight:.semibold)).foregroundStyle(.secondary);HStack(alignment:.firstTextBaseline,spacing:5){Text(shown.formatted(.number.precision(.fractionLength(precision)))).font(.system(size:32,weight:.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6);Text(unit).font(.system(size:15)).foregroundStyle(.secondary)};Text(detail).font(.system(size:12)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    func adjustOverlap(_ direction:Int){NSApp.keyWindow?.makeFirstResponder(nil);let p=(model.input.overlap*100_000).rounded()/1000;model.input.overlap=min(95,max(0,direction>0 ? (floor(p/5)+1)*5:(ceil(p/5)-1)*5))/100}
    func adjustManual(na:Bool,direction:Int){NSApp.keyWindow?.makeFirstResponder(nil);if na{model.input.na=min(0.99,max(0.01,((model.input.na+Double(direction)*0.01)*100).rounded()/100))}else{model.input.magnification=min(50,max(1,model.input.magnification+Double(direction)))}}
}
