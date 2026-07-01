using System.Windows;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// Annotation editor window. This task (5.1) renders the document and exports it; drawing tools, the toolbar/
/// inspector, undo/redo, and sticky style land in tasks 5.2–5.3.
/// </summary>
public partial class EditorWindow : Window
{
    private readonly BitmapSource _baseImage;
    private EditorDocument _document;

    public Action<BitmapSource>? OnCopy { get; set; }
    public Action<BitmapSource>? OnSave { get; set; }
    public Action<BitmapSource>? OnAddToStack { get; set; }
    public Action<AnnotationStyle>? StyleChanged { get; set; }

    public EditorWindow(BitmapSource image, AnnotationStyle? defaultStyle = null)
    {
        InitializeComponent();
        _baseImage = image;
        _document = new EditorDocument(new PxSize(image.PixelWidth, image.PixelHeight));
        Redraw();
    }

    // Phase 5.2 tools mutate _document (and reassign it on crop) then call Redraw().
    private void Redraw() => CanvasImage.Source = DocumentRenderer.Render(_document, _baseImage);

    private BitmapSource Export() => DocumentRenderer.Render(_document, _baseImage);

    private void Done_Click(object sender, RoutedEventArgs e) => Close();
    private void Copy_Click(object sender, RoutedEventArgs e) => OnCopy?.Invoke(Export());
    private void Save_Click(object sender, RoutedEventArgs e) { OnSave?.Invoke(Export()); Close(); }
    private void Stack_Click(object sender, RoutedEventArgs e) { OnAddToStack?.Invoke(Export()); Close(); }
}
