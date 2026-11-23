import os, json
from picosvg.svg import SVG
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path
import pathops
names=sorted(f[:-4] for f in os.listdir('out'))
UPM=1024; S=UPM/24
glyphs={'.notdef':None}; cmap={}; order=['.notdef']; codes={}
for i,n in enumerate(names):
    svg=SVG.parse('out/'+n+'.svg').topicosvg()
    p=pathops.Path()
    for shape in svg.shapes():
        sp=pathops.Path()
        parse_path(shape.d, sp.getPen())
        p=pathops.op(p, sp, pathops.PathOp.UNION)
    p.simplify()
    pen=TTGlyphPen(None)
    # flip y: font y up
    tp=TransformPen(Cu2QuPen(pen,1.0,reverse_direction=True),(S,0,0,-S,0,UPM))
    p.draw(tp)
    gn='i_'+n.replace('-','_')
    glyphs[gn]=pen.glyph(); order.append(gn)
    code=0xE000+i; cmap[code]=gn; codes[n]=code
fb=FontBuilder(UPM,isTTF=True)
fb.setupGlyphOrder(order); fb.setupCharacterMap(cmap)
empty=TTGlyphPen(None).glyph()
glyphs['.notdef']=empty
fb.setupGlyf(glyphs)
glyf=fb.font['glyf']
def lsb(g):
    gl=glyf[g]; gl.recalcBounds(glyf)
    return getattr(gl,'xMin',0) if gl.numberOfContours else 0
# lsb must equal each glyph's xMin, or renderers shift the drawing left.
fb.setupHorizontalMetrics({g:(UPM,lsb(g)) for g in order})
fb.setupHorizontalHeader(ascent=UPM,descent=0)
fb.setupNameTable({'familyName':'StizeIcons','styleName':'Regular'})
fb.setupOS2(sTypoAscender=UPM,sTypoDescender=0,usWinAscent=UPM,usWinDescent=0)
fb.setupPost()
fb.save('StizeIcons.ttf')
json.dump(codes,open('codes.json','w'),indent=0)
print(len(codes))
