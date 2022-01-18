pub const Wrapper = struct {
    raw: *NVGcontext,
    backend: Backend,

    pub const NVGError = error {
        CannotCreateContext,
        UnimplementedBackend,
    };

    pub fn init(backend: Backend, flags: []const CreationFlags) !Wrapper {
        var flag_bitfield: c_int = 0;
        for (flags) |f| {
            flag_bitfield |= @as(c_int, 1) << @enumToInt(f);
        }

        const ctx = switch (backend) {
            .GL3 => nvgCreateGL3(flag_bitfield)
                orelse return error.CannotCreateContext,

            else => return error.UnimplementedBackend,
        };

        return Wrapper {
            .raw = ctx,
            .backend = backend,
        };
    }

    pub fn delete(self: Wrapper) void {
        switch (self.backend) {
            .GL3 => nvgDeleteGL3(self.raw),
            else => unreachable,
        }
    }

    // Frame operations

    pub fn beginFrame(self: Wrapper, window_width: f32, window_height: f32, device_pixel_ratio: f32) void {
        nvgBeginFrame(self.raw, window_width, window_height, device_pixel_ratio);
    }

    pub fn cancelFrame(self: Wrapper) void {
        nvgCancelFrame(self.raw);
    }

    pub fn endFrame(self: Wrapper) void {
        nvgEndFrame(self.raw);
    }

    // Composite operation

    // State Handling

    pub fn save(self: Wrapper) void {
        nvgSave(self.raw);
    }

    pub fn restore(self: Wrapper) void {
        nvgRestore(self.raw);
    }

    pub fn reset(self: Wrapper) void {
        nvgReset(self.raw);
    }

    // Render styles

    pub fn shapeAntiAlias(self: Wrapper, enabled: bool) void {
        nvgShapeAntiAlias(self.raw, @boolToInt(enabled));
    }

    pub fn strokeColor(self: Wrapper, color: NVGcolor) void {
        nvgStrokeColor(self.raw, color);
    }

    pub fn strokePaint(self: Wrapper, paint: NVGpaint) void {
        nvgStrokePaint(self.raw, paint);
    }

    pub fn fillColor(self: Wrapper, color: NVGcolor) void {
        nvgFillColor(self.raw, color);
    }

    pub fn fillPaint(self: Wrapper, paint: NVGpaint) void {
        nvgFillPaint(self.raw, paint);
    }

    pub fn miterLimit(self: Wrapper, limit: f32) void {
        nvgMiterLimit(self.raw, limit);
    }

    pub fn strokeWidth(self: Wrapper, size: f32) void {
        nvgStrokeWidth(self.raw, size);
    }

    pub fn lineCap(self: Wrapper, cap: LineCap) void {
        nvgLineCap(self.raw, @enumToInt(cap));
    }

    pub fn lineJoin(self: Wrapper, join: LineJoin) void {
        nvgLineJoin(self.raw, @enumToInt(join));
    }

    pub fn globalAlpha(self: Wrapper, alpha: f32) void {
        nvgGlobalAlpha(self.raw, alpha);
    }

    // Transforms

    pub fn ResetTransform(self: Wrapper) void {
        nvgResetTransform(self.raw);
    }

    pub fn Transform(self: Wrapper, a: f32, b: f32, c: f32, d: f32, e: f32, f: f32) void {
        nvgTransform(self.raw, a, b, c, d, e, f);
    }

    pub fn Translate(self: Wrapper, x: f32, y: f32) void {
        nvgTranslate(self.raw, x, y);
    }

    pub fn Rotate(self: Wrapper, angle: f32) void {
        nvgRotate(self.raw, angle);
    }

    pub fn SkewX(self: Wrapper, angle: f32) void {
        nvgSkewX(self.raw, angle);
    }

    pub fn SkewY(self: Wrapper, angle: f32) void {
        nvgSkewY(self.raw, angle);
    }

    pub fn Scale(self: Wrapper, x: f32, y: f32) void {
        nvgScale(self.raw, x, y);
    }

    pub fn CurrentTransform(self: Wrapper, xform: [*]f32) void {
        nvgCurrentTransform(self.raw, xform);
    }

    // Images

    fn combine_flags(image_flags: []const ImageFlags) c_int {
        var flags: c_int = 0;
        for (image_flags) |flag| {
            flags |= @as(c_int, 1) << flag;
        }
    }

    pub fn createImage(self: Wrapper, filename: []const u8, image_flags: []const ImageFlags) c_int {
        return nvgCreateImage(self.raw, filename, combine_flags(image_flags));
    }

    pub fn createImageMem(self: Wrapper, image_flags: []const ImageFlags, data: []u8) c_int {
        return nvgCreateImageMem(self.raw, combine_flags(image_flags), data.ptr, data.len);
    }

    pub fn createImageRGBA(self: Wrapper, w: c_int, h: c_int, image_flags: []const ImageFlags, data: []const u8) c_int {
        return nvgCreateImageRGBA(self.raw, w, h, combine_flags(image_flags), data.ptr);
    }

    pub fn updateImage(self: Wrapper, image: c_int, data: []const u8) void {
        nvgUpdateImage(self.raw, image, data);
    }

    pub fn imageSize(self: Wrapper, image: c_int, w: *c_int, h: *c_int) void {
        nvgImageSize(self.raw, image, w, h);
    }

    pub fn deleteImage(self: Wrapper, image: c_int) void {
        nvgDeleteImage(self.raw, image);
    }

    // Paints

    pub fn linearGradient(self: Wrapper, sx: f32, sy: f32, ex: f32, ey: f32, icol: NVGcolor, ocol: NVGcolor) NVGpaint {
        return nvgLinearGradient(self.raw, sx, sy, ex, ey, icol, ocol);
    }

    pub fn boxGradient(self: Wrapper, x: f32, y: f32, w: f32, h: f32, r: f32, f: f32, icol: NVGcolor, ocol: NVGcolor) NVGpaint {
        return nvgBoxGradient(self.raw, x, y, w, h, r, f, icol, ocol);
    }

    pub fn radialGradient(self: Wrapper, cx: f32, cy: f32, inr: f32, outr: f32, icol: NVGcolor, ocol: NVGcolor) NVGpaint {
        return nvgRadialGradient(self.raw, cx, cy, inr, outr, icol, ocol);
    }

    pub fn imagePattern(self: Wrapper, ox: f32, oy: f32, ex: f32, ey: f32, angle: f32, image: c_int, alpha: f32) NVGpaint {
        return nvgImagePattern(self.raw, ox, oy, ex, ey, angle, image, alpha);
    }

    // Scissoring

    pub fn scissor(self: Wrapper, x: f32, y: f32, w: f32, h: f32) void {
        nvgScissor(self.raw, x, y, w, h);
    }

    pub fn intersectScissor(self: Wrapper, x: f32, y: f32, w: f32, h: f32) void {
        nvgIntersectScissor(self.raw, x, y, w, h);
    }

    pub fn resetScissor(self: Wrapper) void {
        nvgResetScissor(self.raw);
    }

    // Paths

    pub fn beginPath(self: Wrapper) void {
        nvgBeginPath(self.raw);
    }

    pub fn moveTo(self: Wrapper, x: f32, y: f32) void {
        nvgMoveTo(self.raw, x, y);
    }

    pub fn lineTo(self: Wrapper, x: f32, y: f32) void {
        nvgLineTo(self.raw, x, y);
    }

    pub fn bezierTo(self: Wrapper, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) void {
        nvgBezierTo(self.raw, c1x, c1y, c2x, c2y, x, y);
    }

    pub fn quadTo(self: Wrapper, cx: f32, cy: f32, x: f32, y: f32) void {
        nvgQuadTo(self.raw, cx, cy, x, y);
    }

    pub fn arcTo(self: Wrapper, x1: f32, y1: f32, x2: f32, y2: f32, radius: f32) void {
        nvgArcTo(self.raw, x1, y1, x2, y2, radius);
    }

    pub fn closePath(self: Wrapper) void {
        nvgClosePath(self.raw);
    }

    pub fn pathWinding(self: Wrapper, dir: PathWinding) void {
        const winding = switch(dir) {
            .ccw, .solid => 1,
            .cw, .hole => 2,
        };

        nvgPathWinding(self.raw, winding);
    }

    pub fn arc(self: Wrapper, cx: f32, cy: f32, r: f32, a0: f32, a1: f32, dir: c_int) void {
        nvgArc(self.raw, cx, cy, r, a0, a1, dir);
    }

    pub fn rect(self: Wrapper, x: f32, y: f32, w: f32, h: f32) void {
        nvgRect(self.raw, x, y, w, h);
    }

    pub fn roundedRect(self: Wrapper, x: f32, y: f32, w: f32, h: f32, r: f32) void {
        nvgRoundedRect(self.raw, x, y, w, h, r);
    }

    pub fn roundedRectVarying(
        self: Wrapper,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        rad_top_left: f32,
        rad_top_right: f32,
        rad_bottom_right: f32,
        rad_bottom_left: f32
    ) void {
        nvgRoundedRectVarying(self.raw, x, y, w, h, rad_top_left, rad_top_right,
            rad_bottom_right, rad_bottom_left);
    }

    pub fn ellipse(self: Wrapper, cx: f32, cy: f32, rx: f32, ry: f32) void {
        nvgEllipse(self.raw, cx, cy, rx, ry);
    }

    pub fn circle(self: Wrapper, cx: f32, cy: f32, r: f32) void {
        nvgCircle(self.raw, cx, cy, r);
    }

    pub fn fill(self: Wrapper) void {
        nvgFill(self.raw);
    }

    pub fn stroke(self: Wrapper) void {
        nvgStroke(self.raw);
    }

    // Text

    pub fn createFont(self: Wrapper, name: []const u8, filename: []const u8) c_int {
        nvgCreateFont(self.raw, name, filename);
    }

    pub fn createFontAtIndex(self: Wrapper, name: []const u8, filename: []const u8, font_index: c_int) c_int {
        nvgCreateFontAtIndex(self.raw, name, filename, font_index);
    }

    pub fn createFontMem(self: Wrapper, name: []const u8, data: []u8, ndata: c_int, free_data: c_int) c_int {
        nvgCreateFontMem(self.raw, name, data, ndata, free_data);
    }

    pub fn createFontMemAtIndex(self: Wrapper, name: []const u8, data: []u8, ndata: c_int, free_data: c_int, font_index: c_int) c_int {
        nvgCreateFontMemAtIndex(self.raw, name, data, ndata, free_data, font_index);
    }

    pub fn findFont(self: Wrapper, name: []const u8) c_int {
        nvgFindFont(self.raw, name);
    }

    pub fn addFallbackFontId(self: Wrapper, base_font: c_int, fallback_font: c_int) c_int {
        nvgAddFallbackFontId(self.raw, base_font, fallback_font);
    }

    pub fn addFallbackFont(self: Wrapper, base_font: []const u8, fallback_font: []const u8) c_int {
        nvgAddFallbackFont(self.raw, base_font, fallback_font);
    }

    pub fn resetFallbackFontsId(self: Wrapper, base_font: c_int) void {
        nvgResetFallbackFontsId(self.raw, base_font);
    }

    pub fn resetFallbackFonts(self: Wrapper, base_font: []const u8) void {
        nvgResetFallbackFonts(self.raw, base_font);
    }

    pub fn fontSize(self: Wrapper, size: f32) void {
        nvgFontSize(self.raw, size);
    }

    pub fn fontBlur(self: Wrapper, blur: f32) void {
        nvgFontBlur(self.raw, blur);
    }

    pub fn textLetterSpacing(self: Wrapper, spacing: f32) void {
        nvgTextLetterSpacing(self.raw, spacing);
    }

    pub fn textLineHeight(self: Wrapper, line_height: f32) void {
        nvgTextLineHeight(self.raw, line_height);
    }

    pub fn textAlign(self: Wrapper, alignment: TextAlign) void {
        nvgTextAlign(self.raw, @as(c_int, 1) << @enumToInt(alignment));
    }

    pub fn fontFaceId(self: Wrapper, font: c_int) void {
        nvgFontFaceId(self.raw, font);
    }

    pub fn fontFace(self: Wrapper, font: []const u8) void {
        nvgFontFace(self.raw, font);
    }

    pub fn text(self: Wrapper, x: f32, y: f32, string: []const u8, end: []const u8) f32 {
        nvgText(self.raw, x, y, string, end);
    }

    pub fn textBox(self: Wrapper, x: f32, y: f32, break_row_width: f32, string: []const u8, end: []const u8) void {
        nvgTextBox(self.raw, x, y, break_row_width, string, end);
    }

    pub fn textBounds(self: Wrapper, x: f32, y: f32, string: []const u8, end: []const u8, bounds: *f32) f32 {
        nvgTextBounds(self.raw, x, y, string, end, bounds);
    }

    pub fn textBoxBounds(self: Wrapper, x: f32, y: f32, break_row_width: f32, string: []const u8, end: []const u8, bounds: *f32) void {
        nvgTextBoxBounds(self.raw, x, y, break_row_width, string, end, bounds);
    }

    pub fn textGlyphPositions(self: Wrapper, x: f32, y: f32, string: []const u8, end: []const u8, positions: *NVGglyphPosition, max_positions: c_int) c_int {
        nvgTextGlyphPositions(self.raw, x, y, string, end, positions, max_positions);
    }

    pub fn textMetrics(self: Wrapper, ascender: *f32, descender: *f32, lineh: *f32) void {
        nvgTextMetrics(self.raw, ascender, descender, lineh);
    }

    pub fn textBreakLines(self: Wrapper, string: []const u8, end: []const u8, break_row_width: f32, rows: *NVGtextRow, max_rows: c_int) c_int {
        nvgTextBreakLines(self.raw, string, end, break_row_width, rows, max_rows);
    }
};

pub const Backend = enum {
    GL3,
    GL2,
};

pub const CreationFlags = enum(u2) {
    anti_alias,
    stencil_strokes,
    debug,
};

pub const NVGcolor = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const NVGpaint = extern struct {
    xform: [6]f32,
    extent: [2]f32,
    radius: f32,
    feather: f32,
    innerColor: NVGcolor,
    outerColor: NVGcolor,
    image: c_int,
};

pub const PathWinding = enum {
    ccw,
    solid,

    cw,
    hole,
};

pub const LineCap = enum(u3) {
    butt   = 0,
    round  = 1,
    square = 2,
};

pub const LineJoin = enum(u3) {
    round = 1,
    bevel = 3,
    miter = 4,
};

pub const TextAlign = enum(u3) {
    left,
    center,
    right,

    top,
    middle,
    bottom,
    baseline,
};

// Used for `nvgGlobalCompositeOperation`, not implemented yet
pub const BlendFactor = enum(c_int) {
    zero = 1<<0,
    one = 1<<1,
    src_color = 1<<2,
    one_minus_src_color = 1<<3,
    dst_color = 1<<4,
    one_minus_dst_color = 1<<5,
    src_alpha = 1<<6,
    one_minus_src_alpha = 1<<7,
    dst_alpha = 1<<8,
    one_minus_dst_alpha = 1<<9,
    src_alpha_saturate = 1<<10,
};

pub const NVGglyphPosition = extern struct {
    str: [*c]const u8,
    x: f32,
    minx: f32,
    maxx: f32,
};

pub const NVGtextRow = extern struct {
    start: [*c]const u8,
    end: [*c]const u8,
    next: [*c]const u8,
    width: f32,
    minx: f32,
    maxx: f32,
};

//pub const ImageFlags = enum(c_int) {
//    image_generate_mipmaps = 1<<0,
//    image_repeatx          = 1<<1,
//    image_repeaty          = 1<<2,
//    image_flipy            = 1<<3,
//    image_premultiplied    = 1<<4,
//    image_nearest          = 1<<5,
//};
pub const ImageFlags = enum(u3) {
    image_generate_mipmaps,
    image_repeatx,
    image_repeaty,
    image_flipy,
    image_premultiplied,
    image_nearest,
};

const NVGcontext = opaque {};


pub extern fn nvgBeginFrame(ctx: ?*NVGcontext, windowWidth: f32, windowHeight: f32, devicePixelRatio: f32) void;
pub extern fn nvgCancelFrame(ctx: ?*NVGcontext) void;
pub extern fn nvgEndFrame(ctx: ?*NVGcontext) void;
pub extern fn nvgGlobalCompositeOperation(ctx: ?*NVGcontext, op: c_int) void;
pub extern fn nvgGlobalCompositeBlendFunc(ctx: ?*NVGcontext, sfactor: c_int, dfactor: c_int) void;
pub extern fn nvgGlobalCompositeBlendFuncSeparate(ctx: ?*NVGcontext, srcRGB: c_int, dstRGB: c_int, srcAlpha: c_int, dstAlpha: c_int) void;
pub extern fn nvgRGB(r: u8, g: u8, b: u8) NVGcolor;
pub extern fn nvgRGBf(r: f32, g: f32, b: f32) NVGcolor;
pub extern fn nvgRGBA(r: u8, g: u8, b: u8, a: u8) NVGcolor;
pub extern fn nvgRGBAf(r: f32, g: f32, b: f32, a: f32) NVGcolor;
pub extern fn nvgLerpRGBA(c0: NVGcolor, c1: NVGcolor, u: f32) NVGcolor;
pub extern fn nvgTransRGBA(c0: NVGcolor, a: u8) NVGcolor;
pub extern fn nvgTransRGBAf(c0: NVGcolor, a: f32) NVGcolor;
pub extern fn nvgHSL(h: f32, s: f32, l: f32) NVGcolor;
pub extern fn nvgHSLA(h: f32, s: f32, l: f32, a: u8) NVGcolor;
pub extern fn nvgSave(ctx: ?*NVGcontext) void;
pub extern fn nvgRestore(ctx: ?*NVGcontext) void;
pub extern fn nvgReset(ctx: ?*NVGcontext) void;
pub extern fn nvgShapeAntiAlias(ctx: ?*NVGcontext, enabled: c_int) void;
pub extern fn nvgStrokeColor(ctx: ?*NVGcontext, color: NVGcolor) void;
pub extern fn nvgStrokePaint(ctx: ?*NVGcontext, paint: NVGpaint) void;

pub extern fn nvgFillColor(ctx: ?*NVGcontext, color: NVGcolor) void;

pub extern fn nvgFillPaint(ctx: ?*NVGcontext, paint: NVGpaint) void;
pub extern fn nvgMiterLimit(ctx: ?*NVGcontext, limit: f32) void;
pub extern fn nvgStrokeWidth(ctx: ?*NVGcontext, size: f32) void;
pub extern fn nvgLineCap(ctx: ?*NVGcontext, cap: c_int) void;
pub extern fn nvgLineJoin(ctx: ?*NVGcontext, join: c_int) void;
pub extern fn nvgGlobalAlpha(ctx: ?*NVGcontext, alpha: f32) void;
pub extern fn nvgResetTransform(ctx: ?*NVGcontext) void;
pub extern fn nvgTransform(ctx: ?*NVGcontext, a: f32, b: f32, c: f32, d: f32, e: f32, f: f32) void;
pub extern fn nvgTranslate(ctx: ?*NVGcontext, x: f32, y: f32) void;
pub extern fn nvgRotate(ctx: ?*NVGcontext, angle: f32) void;
pub extern fn nvgSkewX(ctx: ?*NVGcontext, angle: f32) void;
pub extern fn nvgSkewY(ctx: ?*NVGcontext, angle: f32) void;
pub extern fn nvgScale(ctx: ?*NVGcontext, x: f32, y: f32) void;
pub extern fn nvgCurrentTransform(ctx: ?*NVGcontext, xform: [*c]f32) void;
pub extern fn nvgTransformIdentity(dst: [*c]f32) void;
pub extern fn nvgTransformTranslate(dst: [*c]f32, tx: f32, ty: f32) void;
pub extern fn nvgTransformScale(dst: [*c]f32, sx: f32, sy: f32) void;
pub extern fn nvgTransformRotate(dst: [*c]f32, a: f32) void;
pub extern fn nvgTransformSkewX(dst: [*c]f32, a: f32) void;
pub extern fn nvgTransformSkewY(dst: [*c]f32, a: f32) void;
pub extern fn nvgTransformMultiply(dst: [*c]f32, src: [*c]const f32) void;
pub extern fn nvgTransformPremultiply(dst: [*c]f32, src: [*c]const f32) void;
pub extern fn nvgTransformInverse(dst: [*c]f32, src: [*c]const f32) c_int;
pub extern fn nvgTransformPoint(dstx: [*c]f32, dsty: [*c]f32, xform: [*c]const f32, srcx: f32, srcy: f32) void;
pub extern fn nvgDegToRad(deg: f32) f32;
pub extern fn nvgRadToDeg(rad: f32) f32;
pub extern fn nvgCreateImage(ctx: ?*NVGcontext, filename: [*c]const u8, imageFlags: c_int) c_int;
pub extern fn nvgCreateImageMem(ctx: ?*NVGcontext, imageFlags: c_int, data: [*c]u8, ndata: c_int) c_int;
pub extern fn nvgCreateImageRGBA(ctx: ?*NVGcontext, w: c_int, h: c_int, imageFlags: c_int, data: [*c]const u8) c_int;
pub extern fn nvgUpdateImage(ctx: ?*NVGcontext, image: c_int, data: [*c]const u8) void;
pub extern fn nvgImageSize(ctx: ?*NVGcontext, image: c_int, w: [*c]c_int, h: [*c]c_int) void;
pub extern fn nvgDeleteImage(ctx: ?*NVGcontext, image: c_int) void;
pub extern fn nvgLinearGradient(ctx: ?*NVGcontext, sx: f32, sy: f32, ex: f32, ey: f32, icol: NVGcolor, ocol: NVGcolor) NVGpaint;
pub extern fn nvgBoxGradient(ctx: ?*NVGcontext, x: f32, y: f32, w: f32, h: f32, r: f32, f: f32, icol: NVGcolor, ocol: NVGcolor) NVGpaint;
pub extern fn nvgRadialGradient(ctx: ?*NVGcontext, cx: f32, cy: f32, inr: f32, outr: f32, icol: NVGcolor, ocol: NVGcolor) NVGpaint;
pub extern fn nvgImagePattern(ctx: ?*NVGcontext, ox: f32, oy: f32, ex: f32, ey: f32, angle: f32, image: c_int, alpha: f32) NVGpaint;
pub extern fn nvgScissor(ctx: ?*NVGcontext, x: f32, y: f32, w: f32, h: f32) void;
pub extern fn nvgIntersectScissor(ctx: ?*NVGcontext, x: f32, y: f32, w: f32, h: f32) void;
pub extern fn nvgResetScissor(ctx: ?*NVGcontext) void;
pub extern fn nvgBeginPath(ctx: ?*NVGcontext) void;
pub extern fn nvgMoveTo(ctx: ?*NVGcontext, x: f32, y: f32) void;
pub extern fn nvgLineTo(ctx: ?*NVGcontext, x: f32, y: f32) void;
pub extern fn nvgBezierTo(ctx: ?*NVGcontext, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) void;
pub extern fn nvgQuadTo(ctx: ?*NVGcontext, cx: f32, cy: f32, x: f32, y: f32) void;
pub extern fn nvgArcTo(ctx: ?*NVGcontext, x1: f32, y1: f32, x2: f32, y2: f32, radius: f32) void;
pub extern fn nvgClosePath(ctx: ?*NVGcontext) void;
pub extern fn nvgPathWinding(ctx: ?*NVGcontext, dir: c_int) void;
pub extern fn nvgArc(ctx: ?*NVGcontext, cx: f32, cy: f32, r: f32, a0: f32, a1: f32, dir: c_int) void;
pub extern fn nvgRect(ctx: ?*NVGcontext, x: f32, y: f32, w: f32, h: f32) void;
pub extern fn nvgRoundedRect(ctx: ?*NVGcontext, x: f32, y: f32, w: f32, h: f32, r: f32) void;
pub extern fn nvgRoundedRectVarying(ctx: ?*NVGcontext, x: f32, y: f32, w: f32, h: f32, radTopLeft: f32, radTopRight: f32, radBottomRight: f32, radBottomLeft: f32) void;
pub extern fn nvgEllipse(ctx: ?*NVGcontext, cx: f32, cy: f32, rx: f32, ry: f32) void;
pub extern fn nvgCircle(ctx: ?*NVGcontext, cx: f32, cy: f32, r: f32) void;
pub extern fn nvgFill(ctx: ?*NVGcontext) void;
pub extern fn nvgStroke(ctx: ?*NVGcontext) void;
pub extern fn nvgCreateFont(ctx: ?*NVGcontext, name: [*c]const u8, filename: [*c]const u8) c_int;
pub extern fn nvgCreateFontAtIndex(ctx: ?*NVGcontext, name: [*c]const u8, filename: [*c]const u8, fontIndex: c_int) c_int;
pub extern fn nvgCreateFontMem(ctx: ?*NVGcontext, name: [*c]const u8, data: [*c]u8, ndata: c_int, freeData: c_int) c_int;
pub extern fn nvgCreateFontMemAtIndex(ctx: ?*NVGcontext, name: [*c]const u8, data: [*c]u8, ndata: c_int, freeData: c_int, fontIndex: c_int) c_int;
pub extern fn nvgFindFont(ctx: ?*NVGcontext, name: [*c]const u8) c_int;
pub extern fn nvgAddFallbackFontId(ctx: ?*NVGcontext, baseFont: c_int, fallbackFont: c_int) c_int;
pub extern fn nvgAddFallbackFont(ctx: ?*NVGcontext, baseFont: [*c]const u8, fallbackFont: [*c]const u8) c_int;
pub extern fn nvgResetFallbackFontsId(ctx: ?*NVGcontext, baseFont: c_int) void;
pub extern fn nvgResetFallbackFonts(ctx: ?*NVGcontext, baseFont: [*c]const u8) void;
pub extern fn nvgFontSize(ctx: ?*NVGcontext, size: f32) void;
pub extern fn nvgFontBlur(ctx: ?*NVGcontext, blur: f32) void;
pub extern fn nvgTextLetterSpacing(ctx: ?*NVGcontext, spacing: f32) void;
pub extern fn nvgTextLineHeight(ctx: ?*NVGcontext, lineHeight: f32) void;
pub extern fn nvgTextAlign(ctx: ?*NVGcontext, @"align": c_int) void;
pub extern fn nvgFontFaceId(ctx: ?*NVGcontext, font: c_int) void;
pub extern fn nvgFontFace(ctx: ?*NVGcontext, font: [*c]const u8) void;
pub extern fn nvgText(ctx: ?*NVGcontext, x: f32, y: f32, string: [*c]const u8, end: [*c]const u8) f32;
pub extern fn nvgTextBox(ctx: ?*NVGcontext, x: f32, y: f32, breakRowWidth: f32, string: [*c]const u8, end: [*c]const u8) void;
pub extern fn nvgTextBounds(ctx: ?*NVGcontext, x: f32, y: f32, string: [*c]const u8, end: [*c]const u8, bounds: [*c]f32) f32;
pub extern fn nvgTextBoxBounds(ctx: ?*NVGcontext, x: f32, y: f32, breakRowWidth: f32, string: [*c]const u8, end: [*c]const u8, bounds: [*c]f32) void;
pub extern fn nvgTextGlyphPositions(ctx: ?*NVGcontext, x: f32, y: f32, string: [*c]const u8, end: [*c]const u8, positions: [*c]NVGglyphPosition, maxPositions: c_int) c_int;
pub extern fn nvgTextMetrics(ctx: ?*NVGcontext, ascender: [*c]f32, descender: [*c]f32, lineh: [*c]f32) void;
pub extern fn nvgTextBreakLines(ctx: ?*NVGcontext, string: [*c]const u8, end: [*c]const u8, breakRowWidth: f32, rows: [*c]NVGtextRow, maxRows: c_int) c_int;
pub const NVG_TEXTURE_ALPHA: c_int = 1;
pub const NVG_TEXTURE_RGBA: c_int = 2;
pub const enum_NVGtexture = c_uint;
pub extern fn nvgDebugDumpPathCache(ctx: ?*NVGcontext) void;
pub const NVG_ANTIALIAS: c_int = 1;
pub const NVG_STENCIL_STROKES: c_int = 2;
pub const NVG_DEBUG: c_int = 4;
pub const enum_NVGcreateFlags = c_uint;
pub extern fn nvgCreateGL3(flags: c_int) ?*NVGcontext;
pub extern fn nvgDeleteGL3(ctx: ?*NVGcontext) void;
//pub extern fn nvglCreateImageFromHandleGL3(ctx: ?*NVGcontext, textureId: GLuint, w: c_int, h: c_int, flags: c_int) c_int;
//pub extern fn nvglImageHandleGL3(ctx: ?*NVGcontext, image: c_int) GLuint;
