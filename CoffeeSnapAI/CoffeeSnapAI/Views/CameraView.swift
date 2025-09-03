import SwiftUI
import PhotosUI

struct CameraView: View {
    @EnvironmentObject var coffeeStore: CoffeeStore
    @StateObject private var cameraService = CameraService()
    @StateObject private var mlService = MLService()
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingImagePicker = false
    @State private var showingResults = false
    @State private var isFlashOn = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera preview or permission prompt
                if cameraService.isPermissionGranted {
                    cameraPreview
                } else {
                    permissionPrompt
                }
                
                // Overlay controls
                VStack {
                    // Top controls
                    topControls
                    
                    Spacer()
                    
                    // Bottom controls
                    bottomControls
                }
                .padding()
                
                // Analysis overlay
                if mlService.isAnalyzing {
                    analysisOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .onAppear {
                cameraService.checkPermissions()
                if cameraService.isPermissionGranted {
                    cameraService.startSession()
                }
            }
            .onDisappear {
                cameraService.stopSession()
            }
            .onChange(of: cameraService.capturedImage) { image in
                if let image = image {
                    analyzeImage(image)
                }
            }
            .onChange(of: selectedPhoto) { newPhoto in
                if let newPhoto = newPhoto {
                    loadPhotoFromPicker(newPhoto)
                }
            }
            .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
                Button("Settings") {
                    openAppSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable camera access in Settings to take photos of your coffee.")
            }
            .sheet(isPresented: $showingResults) {
                if let result = mlService.analysisResult {
                    CoffeeAnalysisResultView(
                        coffee: result,
                        onSave: { savedCoffee in
                            coffeeStore.addAnalyzedCoffee(savedCoffee)
                            dismiss()
                        },
                        onDismiss: {
                            showingResults = false
                            mlService.analysisResult = nil
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Camera Preview
    private var cameraPreview: some View {
        ZStack {
            if let previewLayer = cameraService.getPreviewLayer() {
                CameraPreview(previewLayer: previewLayer)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(Color.black)
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("Initializing Camera...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            }
            
            // Camera frame overlay
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColor.cream, lineWidth: 3)
                .frame(width: 280, height: 280)
                .overlay(
                    VStack {
                        HStack {
                            cornerIndicator
                            Spacer()
                            cornerIndicator
                        }
                        Spacer()
                        HStack {
                            cornerIndicator
                            Spacer()
                            cornerIndicator
                        }
                    }
                    .padding(8)
                )
        }
    }
    
    // MARK: - Permission Prompt
    private var permissionPrompt: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(AppColor.caramel)
            
            VStack(spacing: 16) {
                Text("Camera Access Needed")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.primaryText)
                
                Text("CoffeeSnap AI needs camera access to analyze your coffee photos and provide AI-powered insights.")
                    .font(.body)
                    .foregroundColor(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                Button("Enable Camera") {
                    cameraService.requestPermission()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColor.primaryGradient)
                .cornerRadius(12)
                
                Button("Use Photo Library Instead") {
                    showingImagePicker = true
                }
                .font(.subheadline)
                .foregroundColor(AppColor.caramel)
            }
            .padding(.horizontal)
        }
        .padding()
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhoto, matching: .images)
    }
    
    // MARK: - Top Controls
    private var topControls: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(25)
            }
            
            Spacer()
            
            // Flash toggle
            if cameraService.isPermissionGranted {
                Button {
                    isFlashOn.toggle()
                } label: {
                    Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title2)
                        .foregroundColor(isFlashOn ? .yellow : .white)
                        .padding(12)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(25)
                }
            }
        }
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Photo library button
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(16)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(30)
            }
            
            // Capture button
            Button {
                capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .stroke(Color.white, lineWidth: 6)
                        .frame(width: 90, height: 90)
                    
                    if mlService.isAnalyzing {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(AppColor.coffeeBean)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.title)
                            .foregroundColor(AppColor.coffeeBean)
                    }
                }
            }
            .disabled(mlService.isAnalyzing || !cameraService.isPermissionGranted)
            .scaleEffect(mlService.isAnalyzing ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: mlService.isAnalyzing)
            
            // Settings/info button
            Button {
                // Show camera tips or settings
            } label: {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(16)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(30)
            }
        }
        .padding(.bottom, 30)
    }
    
    // MARK: - Analysis Overlay
    private var analysisOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // AI brain animation
                ZStack {
                    Circle()
                        .stroke(AppColor.caramel.opacity(0.3), lineWidth: 4)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(AppColor.caramel, lineWidth: 4)
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: mlService.isAnalyzing)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(AppColor.caramel)
                }
                
                VStack(spacing: 8) {
                    Text("Analyzing Your Coffee...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("AI is identifying coffee type and characteristics")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    // MARK: - Corner Indicator
    private var cornerIndicator: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(AppColor.cream)
            .frame(width: 20, height: 20)
            .opacity(0.8)
    }
    
    // MARK: - Helper Methods
    private func capturePhoto() {
        if cameraService.isPermissionGranted {
            cameraService.capturePhoto()
        } else {
            showingPermissionAlert = true
        }
    }
    
    private func analyzeImage(_ image: UIImage) {
        mlService.analyzeCoffeeImage(image) { result in
            if let result = result {
                mlService.analysisResult = result
                showingResults = true
            }
        }
    }
    
    private func loadPhotoFromPicker(_ photoItem: PhotosPickerItem) {
        photoItem.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.analyzeImage(image)
                    }
                }
            case .failure(let error):
                print("Failed to load photo: \(error)")
            }
        }
    }
    
    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Coffee Analysis Result View
struct CoffeeAnalysisResultView: View {
    let coffee: AnalyzedCoffee
    let onSave: (AnalyzedCoffee) -> Void
    let onDismiss: () -> Void
    
    @State private var userNotes: String = ""
    @State private var userRating: Double = 0
    @State private var animateResult = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with image and basic info
                    resultHeader
                    
                    // Confidence and analysis
                    confidenceSection
                    
                    // Coffee details
                    coffeeDetailsSection
                    
                    // Flavor profile
                    flavorProfileSection
                    
                    // Recommendations
                    recommendationsSection
                    
                    // User input section
                    userInputSection
                }
                .padding()
            }
            .navigationTitle("Analysis Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retake") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCoffeeAnalysis()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            userNotes = coffee.notes
            userRating = coffee.rating ?? 0
            animateResult = true
        }
    }
    
    // MARK: - Result Header
    private var resultHeader: some View {
        VStack(spacing: 16) {
            // Coffee image
            if let imageData = coffee.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .cornerRadius(20)
                    .clipped()
                    .shadow(color: AppColor.shadowColor, radius: 8, x: 0, y: 4)
                    .scaleEffect(animateResult ? 1.0 : 0.8)
                    .animation(.spring(response: 0.6), value: animateResult)
            }
            
            // Coffee type with emoji
            HStack {
                Text(coffee.coffeeType.emoji)
                    .font(.largeTitle)
                
                Text(coffee.coffeeType.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.primaryText)
            }
            .scaleEffect(animateResult ? 1.0 : 0.5)
            .animation(.spring(response: 0.8).delay(0.2), value: animateResult)
        }
    }
    
    // MARK: - Confidence Section
    private var confidenceSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile.fill")
                    .foregroundColor(AppColor.caramel)
                
                Text("AI Confidence")
                    .font(.headline)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
            }
            
            HStack {
                Text("\(Int(coffee.confidence * 100))%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                ProgressView(value: coffee.confidence)
                    .progressViewStyle(LinearProgressViewStyle(tint: confidenceColor))
                    .frame(width: 150)
            }
            
            Text(confidenceDescription)
                .font(.caption)
                .foregroundColor(AppColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Coffee Details Section
    private var coffeeDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coffee Details")
                .font(.headline)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 12) {
                DetailRow(title: "Type", value: coffee.coffeeType.rawValue, icon: "cup.and.saucer.fill")
                DetailRow(title: "Roast Level", value: coffee.roastLevel.rawValue, icon: "flame.fill")
                if let brewMethod = coffee.brewMethod {
                    DetailRow(title: "Suggested Brew", value: brewMethod, icon: "drop.fill")
                }
                if let origin = coffee.origin {
                    DetailRow(title: "Likely Origin", value: origin, icon: "globe")
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Flavor Profile Section
    private var flavorProfileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Flavor Profile")
                .font(.headline)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 12) {
                FlavorBar(label: "Acidity", value: coffee.flavorProfile.acidity, color: .yellow)
                FlavorBar(label: "Body", value: coffee.flavorProfile.body, color: AppColor.coffeeBean)
                FlavorBar(label: "Sweetness", value: coffee.flavorProfile.sweetness, color: .orange)
                FlavorBar(label: "Bitterness", value: coffee.flavorProfile.bitterness, color: AppColor.espresso)
            }
            
            if !coffee.flavorProfile.flavorNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Flavor Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColor.primaryText)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(coffee.flavorProfile.flavorNotes, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColor.caramel.opacity(0.2))
                                .foregroundColor(AppColor.caramel)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Recommendations Section
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommendations")
                .font(.headline)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 12) {
                ForEach(Array(coffee.recommendations.enumerated()), id: \.offset) { index, recommendation in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppColor.caramel)
                            .frame(width: 20, alignment: .leading)
                        
                        Text(recommendation)
                            .font(.subheadline)
                            .foregroundColor(AppColor.primaryText)
                            .lineLimit(nil)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - User Input Section
    private var userInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Thoughts")
                .font(.headline)
                .foregroundColor(AppColor.primaryText)
            
            VStack(spacing: 16) {
                // Rating
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rating")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColor.primaryText)
                    
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                userRating = Double(star)
                            } label: {
                                Image(systemName: star <= Int(userRating) ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundColor(star <= Int(userRating) ? .yellow : AppColor.tertiaryText)
                            }
                        }
                        
                        Spacer()
                    }
                }
                
                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColor.primaryText)
                    
                    TextField("Add your thoughts about this coffee...", text: $userNotes, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }
            }
        }
        .padding()
        .background(AppColor.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    private var confidenceColor: Color {
        if coffee.confidence > 0.8 {
            return .green
        } else if coffee.confidence > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var confidenceDescription: String {
        if coffee.confidence > 0.8 {
            return "High confidence in coffee type identification"
        } else if coffee.confidence > 0.5 {
            return "Moderate confidence - the identification might need verification"
        } else {
            return "Low confidence - consider taking another photo with better lighting"
        }
    }
    
    // MARK: - Helper Methods
    private func saveCoffeeAnalysis() {
        var updatedCoffee = coffee
        // Update with user input (would need to modify AnalyzedCoffee to be mutable)
        onSave(updatedCoffee)
    }
}

// MARK: - Supporting Views
struct DetailRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(AppColor.caramel)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppColor.secondaryText)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColor.primaryText)
        }
    }
}

struct FlavorBar: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(AppColor.primaryText)
                
                Spacer()
                
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundColor(AppColor.secondaryText)
            }
            
            ProgressView(value: value)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
        }
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size = CGSize.zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentPosition = CGPoint.zero
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentPosition.x + subviewSize.width > maxWidth && currentPosition.x > 0 {
                    // Move to next line
                    currentPosition.x = 0
                    currentPosition.y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(origin: currentPosition, size: subviewSize))
                
                currentPosition.x += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
                maxX = max(maxX, currentPosition.x - spacing)
            }
            
            size = CGSize(width: maxX, height: currentPosition.y + lineHeight)
        }
    }
}

#Preview {
    CameraView()
        .environmentObject(CoffeeStore())
}
