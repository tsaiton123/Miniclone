# Apple MobileCLIP Implementation Plan

To implement Apple MobileCLIP for the iOS note-taking app, we need a pipeline that balances accuracy (not losing small handwriting) with performance (saving battery and memory). Here is a complete, high-efficiency pipeline plan to turn handwritten images into searchable vectors on-device.

## Phase 1: Model Preparation (The Engine)
Since MobileCLIP is originally a PyTorch model, we must convert it to Core ML for optimal performance on the Apple Neural Engine (ANE).

* **Selection**: Choose the MobileCLIP-S1 or S2 variant. These are optimized for mobile latency while maintaining high zero-shot accuracy.
* **Conversion**: Use `coremltools` to convert the model to a `.mlpackage`.
* **Dual Encoders**: We need both the Image Encoder (to index notes) and the Text Encoder (to search them).
* **Quantization**: Apply Float16 or 4-bit quantization to reduce the model size (aim for <100MB) without significant loss in embedding quality.
* **Deployment**: Bundle the `.mlpackage` within the Xcode project.

## Phase 2: Image Pre-processing (The Optimizer)
Handwritten notes on iPad are often high-resolution and long. Resizing a long page into a 224×224 square (standard CLIP input) will make handwriting unreadable.

* **Text Detection (Vision Framework)**: Use `VNDetectTextRectanglesRequest` to find areas where ink actually exists.
* **Intelligent Tiling (Sliding Window)**: Instead of one vector per page, split the page into overlapping 512×512 patches. This ensures the "handwriting features" are large enough for the model to "see."
* **Normalization**: Use vImage or Core Image to adjust contrast and convert to the pixel buffer format required by the Core ML model.

## Phase 3: Embedding Generation (The Vectorizer)
This is where the magic happens on the device.

* **Batch Inference**: If the user just finished a 5-page note, don't run them one by one. Use a batch request to the Core ML model to utilize the ANE's parallel processing.
* **L2 Normalization**: Ensure the output vectors are normalized. This makes calculating "Similarity" much faster later (it turns Cosine Similarity into a simple Dot Product).
* **Background Processing**: Run this on a `.utility` background thread so the iPad's UI remains 120Hz smooth while the user is writing.

## Phase 4: Storage & Indexing (The Library)
We need a place to store these vectors so we can search them in milliseconds.

* **Vector DB (swift-objectbox / ObjectBox Swift)**:
    * Store the Embedding (`[Float]`) as a property.
    * Store Metadata: `pageID`, `rectInPage` (where the tile was), and `timestamp`.
* **Indexing**: Enable HNSW (Hierarchical Navigable Small World) indexing in ObjectBox. This allows the app to find the closest handwriting match among thousands of pages in <5ms.

## Phase 5: Search & Retrieval (The UX)
How the user actually finds their "Coffee Recipe" or "Math Homework."

* **Encoding the Query**: When the user types in the search bar, run that string through the MobileCLIP Text Encoder.
* **Vector Search**: Perform a "Nearest Neighbor" search in ObjectBox using the text vector against the stored image vectors.
* **Result Highlighting**:
    * Retrieve the `rectInPage` metadata from the winning vector.
    * Visually highlight that specific area of the handwriting in the UI.

## Summary of the Tech Stack

| Component | Technology |
| --- | --- |
| **Model** | Apple MobileCLIP (Core ML) |
| **Vision** | `VNImageRequestHandler` + `VNDetectTextRectanglesRequest` |
| **Storage** | ObjectBox Swift (for on-device Vector Search) |
| **Inference** | Apple Neural Engine (ANE) via `MLModel` |

### Pro-Tip for Note App:
Since handwriting is the focus, it is recommended to "double-index." Use Apple's `VNRecognizeTextRequest` (OCR) to get raw text for keyword matching, and MobileCLIP for "semantic" matching (e.g., searching for "Fruit" and finding a drawing or note about "Apples").
