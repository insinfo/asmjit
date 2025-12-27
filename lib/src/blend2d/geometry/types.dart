// Blend2D Geometry Types
// Port of blend2d/core/geometry.h

import 'dart:math' as math;

/// 2D point with double precision coordinates.
class BLPoint {
  final double x;
  final double y;

  const BLPoint(this.x, this.y);

  const BLPoint.zero()
      : x = 0.0,
        y = 0.0;

  BLPoint operator +(BLPoint other) => BLPoint(x + other.x, y + other.y);
  BLPoint operator -(BLPoint other) => BLPoint(x - other.x, y - other.y);
  BLPoint operator *(double scalar) => BLPoint(x * scalar, y * scalar);
  BLPoint operator /(double scalar) => BLPoint(x / scalar, y / scalar);

  double get length => math.sqrt(x * x + y * y);
  double distanceTo(BLPoint other) => (this - other).length;

  @override
  String toString() => 'BLPoint($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is BLPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 2D point with integer coordinates.
class BLPointI {
  final int x;
  final int y;

  const BLPointI(this.x, this.y);

  const BLPointI.zero()
      : x = 0,
        y = 0;

  BLPointI operator +(BLPointI other) => BLPointI(x + other.x, y + other.y);
  BLPointI operator -(BLPointI other) => BLPointI(x - other.x, y - other.y);
  BLPointI operator *(int scalar) => BLPointI(x * scalar, y * scalar);
  BLPointI operator ~/(int scalar) => BLPointI(x ~/ scalar, y ~/ scalar);

  BLPoint toDouble() => BLPoint(x.toDouble(), y.toDouble());

  @override
  String toString() => 'BLPointI($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is BLPointI && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 2D size with double precision.
class BLSize {
  final double w;
  final double h;

  const BLSize(this.w, this.h);

  const BLSize.zero()
      : w = 0.0,
        h = 0.0;

  BLSize operator +(BLSize other) => BLSize(w + other.w, h + other.h);
  BLSize operator -(BLSize other) => BLSize(w - other.w, h - other.h);
  BLSize operator *(double scalar) => BLSize(w * scalar, h * scalar);
  BLSize operator /(double scalar) => BLSize(w / scalar, h / scalar);

  double get area => w * h;

  @override
  String toString() => 'BLSize($w, $h)';

  @override
  bool operator ==(Object other) =>
      other is BLSize && w == other.w && h == other.h;

  @override
  int get hashCode => Object.hash(w, h);
}

/// 2D size with integer dimensions.
class BLSizeI {
  final int w;
  final int h;

  const BLSizeI(this.w, this.h);

  const BLSizeI.zero()
      : w = 0,
        h = 0;

  BLSizeI operator +(BLSizeI other) => BLSizeI(w + other.w, h + other.h);
  BLSizeI operator -(BLSizeI other) => BLSizeI(w - other.w, h - other.h);
  BLSizeI operator *(int scalar) => BLSizeI(w * scalar, h * scalar);
  BLSizeI operator ~/(int scalar) => BLSizeI(w ~/ scalar, h ~/ scalar);

  int get area => w * h;

  BLSize toDouble() => BLSize(w.toDouble(), h.toDouble());

  @override
  String toString() => 'BLSizeI($w, $h)';

  @override
  bool operator ==(Object other) =>
      other is BLSizeI && w == other.w && h == other.h;

  @override
  int get hashCode => Object.hash(w, h);
}

/// 2D rectangle with double precision.
class BLRect {
  final double x;
  final double y;
  final double w;
  final double h;

  const BLRect(this.x, this.y, this.w, this.h);

  const BLRect.zero()
      : x = 0.0,
        y = 0.0,
        w = 0.0,
        h = 0.0;

  BLRect.fromLTRB(double left, double top, double right, double bottom)
      : x = left,
        y = top,
        w = right - left,
        h = bottom - top;

  double get left => x;
  double get top => y;
  double get right => x + w;
  double get bottom => y + h;

  double get area => w * h;

  BLPoint get topLeft => BLPoint(x, y);
  BLPoint get topRight => BLPoint(x + w, y);
  BLPoint get bottomLeft => BLPoint(x, y + h);
  BLPoint get bottomRight => BLPoint(x + w, y + h);

  BLSize get size => BLSize(w, h);

  bool contains(BLPoint point) =>
      point.x >= x && point.x < x + w && point.y >= y && point.y < y + h;

  bool intersects(BLRect other) =>
      x < other.x + other.w &&
      x + w > other.x &&
      y < other.y + other.h &&
      y + h > other.y;

  BLRect? intersection(BLRect other) {
    final l = math.max(x, other.x);
    final t = math.max(y, other.y);
    final r = math.min(x + w, other.x + other.w);
    final b = math.min(y + h, other.y + other.h);
    if (l < r && t < b) {
      return BLRect(l, t, r - l, b - t);
    }
    return null;
  }

  BLRect union(BLRect other) {
    final l = math.min(x, other.x);
    final t = math.min(y, other.y);
    final r = math.max(x + w, other.x + other.w);
    final b = math.max(y + h, other.y + other.h);
    return BLRect(l, t, r - l, b - t);
  }

  @override
  String toString() => 'BLRect($x, $y, $w, $h)';

  @override
  bool operator ==(Object other) =>
      other is BLRect &&
      x == other.x &&
      y == other.y &&
      w == other.w &&
      h == other.h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

/// 2D rectangle with integer coordinates.
class BLRectI {
  final int x;
  final int y;
  final int w;
  final int h;

  const BLRectI(this.x, this.y, this.w, this.h);

  const BLRectI.zero()
      : x = 0,
        y = 0,
        w = 0,
        h = 0;

  BLRectI.fromLTRB(int left, int top, int right, int bottom)
      : x = left,
        y = top,
        w = right - left,
        h = bottom - top;

  int get left => x;
  int get top => y;
  int get right => x + w;
  int get bottom => y + h;

  int get area => w * h;

  BLPointI get topLeft => BLPointI(x, y);
  BLPointI get topRight => BLPointI(x + w, y);
  BLPointI get bottomLeft => BLPointI(x, y + h);
  BLPointI get bottomRight => BLPointI(x + w, y + h);

  BLSizeI get size => BLSizeI(w, h);

  bool contains(BLPointI point) =>
      point.x >= x && point.x < x + w && point.y >= y && point.y < y + h;

  BLRect toDouble() => BLRect(
        x.toDouble(),
        y.toDouble(),
        w.toDouble(),
        h.toDouble(),
      );

  @override
  String toString() => 'BLRectI($x, $y, $w, $h)';

  @override
  bool operator ==(Object other) =>
      other is BLRectI &&
      x == other.x &&
      y == other.y &&
      w == other.w &&
      h == other.h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

/// 2D box (rectangular area) with double precision [x0, y0, x1, y1].
class BLBox {
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  const BLBox(this.x0, this.y0, this.x1, this.y1);

  const BLBox.zero()
      : x0 = 0.0,
        y0 = 0.0,
        x1 = 0.0,
        y1 = 0.0;

  double get width => x1 - x0;
  double get height => y1 - y0;
  double get area => width * height;

  BLRect toRect() => BLRect(x0, y0, x1 - x0, y1 - y0);

  @override
  String toString() => 'BLBox($x0, $y0, $x1, $y1)';

  @override
  bool operator ==(Object other) =>
      other is BLBox &&
      x0 == other.x0 &&
      y0 == other.y0 &&
      x1 == other.x1 &&
      y1 == other.y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);
}

/// Rounded rectangle.
class BLRoundRect {
  final double x;
  final double y;
  final double w;
  final double h;
  final double rx;
  final double ry;

  const BLRoundRect(this.x, this.y, this.w, this.h, this.rx, this.ry);

  BLRoundRect.fromRect(BLRect rect, double radiusX, double radiusY)
      : x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
        rx = radiusX,
        ry = radiusY;

  BLRect get rect => BLRect(x, y, w, h);

  @override
  String toString() => 'BLRoundRect($x, $y, $w, $h, rx=$rx, ry=$ry)';
}

/// Circle.
class BLCircle {
  final double cx;
  final double cy;
  final double r;

  const BLCircle(this.cx, this.cy, this.r);

  BLPoint get center => BLPoint(cx, cy);
  double get area => math.pi * r * r;
  double get circumference => 2.0 * math.pi * r;

  @override
  String toString() => 'BLCircle($cx, $cy, r=$r)';
}

/// Ellipse.
class BLEllipse {
  final double cx;
  final double cy;
  final double rx;
  final double ry;

  const BLEllipse(this.cx, this.cy, this.rx, this.ry);

  BLPoint get center => BLPoint(cx, cy);

  @override
  String toString() => 'BLEllipse($cx, $cy, rx=$rx, ry=$ry)';
}

/// Line segment.
class BLLine {
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  const BLLine(this.x0, this.y0, this.x1, this.y1);

  BLLine.fromPoints(BLPoint p0, BLPoint p1)
      : x0 = p0.x,
        y0 = p0.y,
        x1 = p1.x,
        y1 = p1.y;

  BLPoint get p0 => BLPoint(x0, y0);
  BLPoint get p1 => BLPoint(x1, y1);

  double get length => math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));

  @override
  String toString() => 'BLLine($x0, $y0, $x1, $y1)';
}

/// Triangle.
class BLTriangle {
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const BLTriangle(this.x0, this.y0, this.x1, this.y1, this.x2, this.y2);

  BLTriangle.fromPoints(BLPoint p0, BLPoint p1, BLPoint p2)
      : x0 = p0.x,
        y0 = p0.y,
        x1 = p1.x,
        y1 = p1.y,
        x2 = p2.x,
        y2 = p2.y;

  BLPoint get p0 => BLPoint(x0, y0);
  BLPoint get p1 => BLPoint(x1, y1);
  BLPoint get p2 => BLPoint(x2, y2);

  double get area {
    // Using cross product formula
    return 0.5 * ((x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)).abs();
  }

  @override
  String toString() => 'BLTriangle($x0, $y0, $x1, $y1, $x2, $y2)';
}
