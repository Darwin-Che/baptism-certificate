from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN
from pptx.dml.color import RGBColor
import sys
import shlex

# Example input format from stdin:
"""
template.pptx output.pptx
img headshot.jpg
left=2 top=3 w=3
txt Hello from Python
left=1 top=1 w=6 h=1.5
fontsz=32 align=center
txt Person's name
left=1 top=1 w=6 h=1.5
fontsz=12 align=center
"""

def parse_stdin():
    lines = []
    for line in sys.stdin:
        line = line.rstrip('\n')
        if line == '':
            break
        lines.append(line)
    # First line: template.pptx output.pptx
    template, output = lines[0].split()
    blocks = []
    i = 1
    while i < len(lines):
        if lines[i].startswith('img '):
            img_path = lines[i].split()[1]
            img_params = {k: float(v) for k, v in (item.split('=') for item in lines[i+1].split())}
            blocks.append({'type': 'img', 'img_path': img_path, 'params': img_params})
            i += 2
        elif lines[i].startswith('txt '):
            txt = lines[i][4:]
            txt_params = {k: float(v) for k, v in (item.split('=') for item in lines[i+1].split())}
            font_params = {}
            font_items = shlex.split(lines[i+2])
            for item in font_items:
                k, v = item.split('=', 1)
                if k == 'fontsz':
                    font_params['fontsz'] = int(v)
                elif k == 'align':
                    font_params['align'] = v
                elif k == 'font':
                    # Remove quotes if present
                    if v.startswith('"') and v.endswith('"'):
                        v = v[1:-1]
                    font_params['font'] = v
            blocks.append({'type': 'txt', 'txt': txt, 'params': txt_params, 'font_params': font_params})
            i += 3
        else:
            i += 1
    return {
        'template_pptx': template,
        'output_pptx': output,
        'blocks': blocks
    }

def modify_slide(
    template_pptx: str,
    output_pptx: str,
    blocks: list
):
    prs = Presentation(template_pptx)
    slide = prs.slides[0]

    for block in blocks:
        if block['type'] == 'img':
            p = block['params']
            slide.shapes.add_picture(
                block['img_path'],
                Inches(p['left']),
                Inches(p['top']),
                width=Inches(p['w'])
            )
        elif block['type'] == 'txt':
            p = block['params']
            f = block['font_params']
            textbox = slide.shapes.add_textbox(
                Inches(p['left']),
                Inches(p['top']),
                Inches(p['w']),
                Inches(p['h']))
            text_frame = textbox.text_frame
            text_frame.clear()
            para = text_frame.paragraphs[0]
            para.text = block['txt']
            para.font.size = Pt(f['fontsz'])
            para.font.bold = True
            # para.font.color.rgb = RGBColor(255, 255, 255)
            if 'font' in f:
                para.font.name = f['font']
            if f['align'] == 'center':
                para.alignment = PP_ALIGN.CENTER
            elif f['align'] == 'left':
                para.alignment = PP_ALIGN.LEFT
            elif f['align'] == 'right':
                para.alignment = PP_ALIGN.RIGHT

    prs.save(output_pptx)

if __name__ == "__main__":
    args = parse_stdin()
    modify_slide(
        template_pptx=args['template_pptx'],
        output_pptx=args['output_pptx'],
        blocks=args['blocks']
    )