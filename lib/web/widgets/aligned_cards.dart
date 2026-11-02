import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Measures real card content before stretching a desktop row to one height.
/// Unlike intrinsic sizing, this supports charts containing LayoutBuilder.
class WebAlignedCards extends MultiChildRenderObjectWidget {
  final List<int> flexes;
  final double spacing;
  const WebAlignedCards({
    super.key,
    required super.children,
    this.flexes = const [],
    this.spacing = 16,
  }) : assert(flexes.length == 0 || flexes.length == children.length);
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderWebAlignedCards(Axis.horizontal, flexes, spacing);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderWebAlignedCards renderObject,
  ) {
    renderObject
      ..flexes = flexes
      ..spacing = spacing;
  }
}

/// Keeps stacked sidebar cards aligned with their neighboring large panel.
class WebStretchCards extends MultiChildRenderObjectWidget {
  final double spacing;
  const WebStretchCards({
    super.key,
    required super.children,
    this.spacing = 16,
  });
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderWebAlignedCards(Axis.vertical, const [], spacing);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderWebAlignedCards renderObject,
  ) {
    renderObject.spacing = spacing;
  }
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

class RenderWebAlignedCards extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardParentData> {
  final Axis axis;
  List<int> _flexes;
  double _spacing;
  RenderWebAlignedCards(this.axis, this._flexes, this._spacing);

  set flexes(List<int> value) {
    if (listEquals(value, _flexes)) {
      return;
    }
    _flexes = List.of(value);
    markNeedsLayout();
  }

  set spacing(double value) {
    if (value == _spacing) {
      return;
    }
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardParentData) {
      child.parentData = _CardParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth);
    if (childCount == 0) {
      size = constraints.constrain(Size(constraints.maxWidth, 0));
      return;
    }
    final width = constraints.maxWidth;
    final gap = _spacing * (childCount - 1);
    final natural = <Size>[];
    final totalFlex = _flexes.isEmpty
        ? childCount
        : _flexes.fold<int>(0, (a, b) => a + b);
    assert(totalFlex > 0);
    var child = firstChild;
    var index = 0;
    var height = 0.0;
    while (child != null) {
      final childWidth = axis == Axis.horizontal
          ? math.max(0.0, width - gap) *
                (_flexes.isEmpty ? 1 : _flexes[index]) /
                totalFlex
          : width;
      child.layout(
        BoxConstraints.tightFor(width: childWidth),
        parentUsesSize: true,
      );
      natural.add(child.size);
      height = axis == Axis.horizontal
          ? math.max(height, child.size.height)
          : height + child.size.height;
      child = (child.parentData! as _CardParentData).nextSibling;
      index++;
    }
    if (axis == Axis.vertical) {
      height += gap;
    }
    size = constraints.constrain(Size(width, height));
    final extra = axis == Axis.vertical
        ? math.max(0.0, size.height - height) / childCount
        : 0.0;
    var offset = 0.0;
    child = firstChild;
    index = 0;
    while (child != null) {
      final cardSize = Size(
        natural[index].width,
        axis == Axis.horizontal ? size.height : natural[index].height + extra,
      );
      // A tight height makes this child a relayout boundary. Descendant-only
      // content changes would then keep the old row height and overflow. Keep
      // the shared height as a minimum so those changes reach this parent and
      // trigger another natural-size measurement.
      child.layout(
        BoxConstraints(
          minWidth: cardSize.width,
          maxWidth: cardSize.width,
          minHeight: cardSize.height,
        ),
        parentUsesSize: true,
      );
      final data = child.parentData! as _CardParentData;
      data.offset = axis == Axis.horizontal
          ? Offset(offset, 0)
          : Offset(0, offset);
      offset +=
          (axis == Axis.horizontal ? cardSize.width : cardSize.height) +
          _spacing;
      child = data.nextSibling;
      index++;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
