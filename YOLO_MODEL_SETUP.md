# YOLO 模型集成指南

本文档说明如何将训练好的 YOLO 模型集成到 CardScanner 应用中。

## ✅ 已实现的功能

- ✅ `YOLOCardDetector` 服务类 - 用于加载和运行 YOLO 模型
- ✅ 与现有 OCR 和卡片检测流程的集成
- ✅ 支持在 Vision 矩形检测和 YOLO 检测之间切换
- ✅ 自动提取卡片信息（OCR + 人脸检测）

## 📋 使用步骤

### 1. 转换 YOLO 模型到 Core ML 格式

YOLO 模型需要转换为 `.mlmodel` 或 `.mlpackage` 格式才能在 iOS 上使用。

#### 方法 A: 使用 coremltools (推荐)

```python
import coremltools as ct

# 对于 PyTorch YOLO 模型
model = ct.convert(
    "your_yolo_model.pt",  # 或 .pth
    source="pytorch",
    inputs=[ct.TensorType(name="image", shape=(1, 3, 640, 640))],  # 根据你的模型调整
    outputs=["boxes", "scores", "classes"],  # 根据你的模型输出调整
    compute_units=ct.ComputeUnit.ALL  # 或 .CPU_AND_NEURAL_ENGINE, .CPU_ONLY
)

# 保存模型
model.save("BaseballCardYOLO.mlpackage")
```

#### 方法 B: 对于 ONNX 格式

```python
import coremltools as ct

model = ct.convert(
    "your_yolo_model.onnx",
    source="onnx",
    compute_units=ct.ComputeUnit.ALL
)

model.save("BaseballCardYOLO.mlpackage")
```

#### 方法 C: 对于 TensorFlow/Keras

```python
import coremltools as ct
import tensorflow as tf

# 加载 TensorFlow 模型
tf_model = tf.keras.models.load_model("your_yolo_model.h5")

# 转换为 Core ML
model = ct.convert(
    tf_model,
    source="tensorflow",
    compute_units=ct.ComputeUnit.ALL
)

model.save("BaseballCardYOLO.mlpackage")
```

### 2. 验证模型输出格式

转换后，检查模型的输入/输出格式：

```python
import coremltools as ct

model = ct.models.MLModel("BaseballCardYOLO.mlpackage")
print(model.input_description)
print(model.output_description)
```

### 3. 添加到 Xcode 项目

1. 在 Xcode 中，右键点击 `CardScanner` 文件夹
2. 选择 "Add Files to CardScanner..."
3. 选择你的 `.mlmodel` 或 `.mlpackage` 文件
4. 确保 "Copy items if needed" 已勾选
5. 确保 "Add to targets: CardScanner" 已勾选
6. 点击 "Add"

### 4. 更新代码中的模型名称

打开 `YOLOCardDetector.swift`，找到这一行：

```swift
guard let modelURL = Bundle.main.url(forResource: "YourYOLOModel", withExtension: "mlmodel") ??
                     Bundle.main.url(forResource: "YourYOLOModel", withExtension: "mlpackage") else {
```

将 `"YourYOLOModel"` 替换为你的实际模型文件名（不带扩展名）。

例如，如果你的模型是 `BaseballCardYOLO.mlpackage`，则改为：

```swift
guard let modelURL = Bundle.main.url(forResource: "BaseballCardYOLO", withExtension: "mlmodel") ??
                     Bundle.main.url(forResource: "BaseballCardYOLO", withExtension: "mlpackage") else {
```

### 5. 配置模型输出解析（如果需要）

YOLO 模型的输出格式可能因版本而异。在 `YOLOCardDetector.swift` 中的 `parseYOLOOutput` 方法中，你可能需要根据你的模型调整解析逻辑。

常见输出格式：

#### YOLOv5/v8 输出格式
```swift
// 输出: [batch, num_detections, 6]
// 每行: [x_center, y_center, width, height, confidence, class]
```

#### YOLOv3/v4 输出格式
```swift
// 输出: [batch, 3*(5+num_classes), grid_h, grid_w]
// 需要后处理 NMS
```

### 6. 启用 YOLO 检测

在 `CameraScannerView.swift` 中，将 `useYOLODetection` 设为 `true`：

```swift
@State private var useYOLODetection = true  // 启用 YOLO 检测
```

或者添加一个 UI 开关让用户选择：

```swift
Toggle("Use YOLO Detection", isOn: $useYOLODetection)
    .padding()
```

## 🔧 模型要求

### 输入格式
- **图像尺寸**: 通常为 640x640 或 416x416（取决于你的模型）
- **颜色空间**: RGB
- **像素值范围**: 0-1 或 0-255（需要在转换时指定）

### 输出格式
- **边界框**: 归一化坐标 (0.0 到 1.0) 或像素坐标
- **置信度**: 0.0 到 1.0
- **类别**: 整数索引或字符串标识符

## 📝 自定义输出解析

如果你的 YOLO 模型输出格式不同，需要修改 `parseYOLOOutput` 方法。

### 示例：自定义输出解析

```swift
private func parseYOLOOutput(from request: VNRequest) -> [YOLODetection] {
    // 访问原始 MLFeatureValue
    guard let featureValue = request.results?.first as? MLFeatureValue,
          let multiArray = featureValue.multiArrayValue else {
        return []
    }
    
    // 解析你的模型特定输出格式
    let shape = multiArray.shape
    // ... 根据你的输出格式解析 ...
    
    return detections
}
```

## 🐛 故障排除

### 问题 1: 模型加载失败
- ✅ 检查模型文件名是否正确
- ✅ 确保模型已添加到项目并包含在 Target 中
- ✅ 检查模型格式（.mlmodel 或 .mlpackage）

### 问题 2: 检测不工作
- ✅ 检查模型的输入尺寸是否匹配
- ✅ 验证 `parseYOLOOutput` 是否正确解析输出
- ✅ 检查控制台日志中的错误信息

### 问题 3: 性能问题
- ✅ 使用 `.mlpackage` 格式（支持 Float16 量化）
- ✅ 在 `coremltools.convert` 中指定 `compute_units`
- ✅ 考虑使用模型量化（Int8）

## 📚 参考资料

- [Core ML Tools Documentation](https://coremltools.readme.io/)
- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [Converting Neural Network Models to Core ML](https://developer.apple.com/documentation/coreml/converting_trained_models_to_core_ml)

## 💡 提示

1. **测试转换后的模型**: 在添加到 iOS 项目前，先用 Python 测试转换后的 Core ML 模型
2. **模型优化**: 考虑使用 Core ML Tools 进行量化以减小模型大小
3. **调试**: 在 `YOLOCardDetector` 中添加更多日志以追踪问题
4. **性能**: 如果实时检测太慢，考虑降低检测频率或使用更小的模型

## 🔄 与现有检测系统的集成

当前实现支持在两种检测方式之间切换：

1. **Vision 矩形检测** (默认): 使用 Vision 框架的通用矩形检测
2. **YOLO 检测**: 使用你的自定义 YOLO 模型进行专门的卡片检测

两种方式都会：
- ✅ 检测卡片位置
- ✅ 使用 OCR 提取文字信息
- ✅ 使用人脸检测验证卡片
- ✅ 提取卡片信息（球员姓名、年份、球队等）

YOLO 模型的优势：
- 🎯 更准确的卡片检测（如果模型专门针对卡片训练）
- 📊 可以识别卡片类型（如不同品牌）
- 👤 可能包含球员识别（如果模型训练了此功能）
