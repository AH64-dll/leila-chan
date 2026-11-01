import cv2
import numpy as np
from scipy.ndimage import binary_fill_holes
import os
import sys

W, H = 768, 1376
WORK_DIR = "/home/amrhares/Documents/qwen dating semulator"
PNG_DIR = os.path.join(WORK_DIR, "png_sprites")
ART_DIR = "/home/amrhares/.gemini/antigravity/brain/1961ef37-e4b1-4149-98ed-bb312010c5fb"
SCRATCH_DIR = os.path.join(ART_DIR, "scratch")
os.makedirs(PNG_DIR, exist_ok=True)
os.makedirs(SCRATCH_DIR, exist_ok=True)

sys.path.append('/tmp')
from test_faces_17_v6 import refs, master_blank_07, build_17_faces_v6, preserve_bangs
from test_pixel_shader_v2 import (
    BAYER_GRID_2X2, get_bayer_grid, warp_grid, get_closed_character_silhouette,
    apply_dithered_aura_30, decorate_state_pixel_accents, draw_pixel_sprite, PAL
)
from test_pixel_shader import apply_boutique_pixel_shader

faces_17 = build_17_faces_v6()

def attach_head_neck_blend(body_img, face_img):
    """
    Keeps the entire head AND chin tip (y=35..282) 100% intact from face_img,
    and feathers across the smooth vertical neck (y=282..289) above the collar (y=295).
    """
    out = body_img.copy()
    head_cut = np.zeros((H, W), dtype=np.float32)
    head_cut[35:283, 235:545] = 1.0
    for y in range(282, 290):
        head_cut[y, 235:545] = max(0.0, (289.0 - y) / 7.0)
    head_cut = cv2.GaussianBlur(head_cut, (0, 0), 2.0)
    m3 = head_cut[:, :, None]
    out = (out.astype(np.float32) * (1.0 - m3) + face_img.astype(np.float32) * m3).astype(np.uint8)
    return out

def make_left_arm_raised_base(left_src_img, right_src_img, split_x=376):
    out = right_src_img.copy()
    mask = np.zeros((H, W), dtype=np.float32)
    mask[200:845, 0:split_x] = 1.0
    mask = cv2.GaussianBlur(mask, (0, 0), 4.0)
    out = (out.astype(np.float32) * (1.0 - mask[:, :, None]) + left_src_img.astype(np.float32) * mask[:, :, None]).astype(np.uint8)
    return out

def build_all_30_raw_bodies():
    """
    Constructs all 30 canonically registered (768x1376) full-body sprites + 00_base_reference
    before the uniform Boutique HD Pixel-Art Visual Novel Shader pass.
    """
    all_raw = {}
    all_raw["00_base_reference"] = refs["00"].copy()

    # Existing 13 reference states (registered on 768x1376):
    all_raw["01_radiant_joy"]          = refs["01"].copy()
    all_raw["02_gentle_relief"]        = refs["02"].copy()
    all_raw["03_playful_smugness"]     = refs["03"].copy()
    all_raw["06_flustered_shyness"]    = refs["06"].copy()
    all_raw["07_stoic_coldness"]       = refs["07"].copy()
    all_raw["11_sudden_shock"]         = refs["11"].copy()
    all_raw["13_nervous_anxiety"]      = refs["13"].copy()
    all_raw["16_bitter_breakdown"]     = refs["16"].copy()
    all_raw["17_fierce_anger"]         = refs["17"].copy()
    all_raw["21_red_eyed_knife_mania"] = refs["21"].copy()
    all_raw["22_unhinged_jaw_laugh"]   = refs["22"].copy()
    all_raw["26_sanity_break_twitch"]  = refs["26"].copy()

    # Fix 12_exhausted_fatigue proportions: gently compress upper head/torso by 0.90x while keeping shoes anchored at y=1348
    # and head top at y=102 (a natural 35px forward slump compared to upright y=67)!
    r12 = refs["12"].copy()
    def warp_12_slump(gx, gy):
        # Upper body (y < 800) scales inward by 0.89x around (382, 420) and sits at y_top ~ 102
        w_upper = np.clip((950.0 - gy) / 450.0, 0.0, 1.0)
        w_upper = w_upper * w_upper * (3.0 - 2.0 * w_upper)
        dx = (gx - 382.0) * (-0.10 * w_upper)
        dy = (gy - 520.0) * (-0.08 * w_upper) + 18.0 * w_upper
        return dx, dy
    all_raw["12_exhausted_fatigue"] = warp_grid(r12, warp_12_slump)

    # ---------------------------------------------------------
    # Now build the 17 synthesized full-body states:
    # ---------------------------------------------------------
    # 04_confident_pride:
    b13 = refs["13"].copy()
    b07 = refs["07"].copy()
    def pride_arm_warp(gx, gy):
        wy = np.exp(-((gy - 510.0) / 55.0)**2)
        wx_l = np.exp(-((gx - 335.0) / 55.0)**2)
        wx_r = np.exp(-((gx - 430.0) / 55.0)**2)
        wy_elbow = np.exp(-((gy - 470.0) / 75.0)**2)
        wx_el_l = np.exp(-((gx - 250.0) / 50.0)**2)
        wx_el_r = np.exp(-((gx - 520.0) / 50.0)**2)
        dx = -34.0 * wy * wx_l + 34.0 * wy * wx_r - 12.0 * wy_elbow * wx_el_l + 12.0 * wy_elbow * wx_el_r
        dy = -4.0 * wy * (wx_l + wx_r)
        return dx, dy
    base_04 = warp_grid(b13, pride_arm_warp)
    center_mask = np.zeros((H, W), dtype=np.float32)
    center_mask[340:620, 336:432] = 1.0
    center_mask = cv2.GaussianBlur(center_mask, (0, 0), 5.0)
    base_04 = (base_04.astype(np.float32) * (1.0 - center_mask[:, :, None]) + b07.astype(np.float32) * center_mask[:, :, None]).astype(np.uint8)
    all_raw["04_confident_pride"] = attach_head_neck_blend(base_04, faces_17["04_confident_pride"])

    # 05_pure_innocence:
    img_05 = attach_head_neck_blend(refs["01"], faces_17["05_pure_innocence"])
    # Subtle curious head tilt (+2.8 deg around neck pivot 382, 280)
    M05 = cv2.getRotationMatrix2D((382, 280), 2.8, 1.0)
    rot_05 = cv2.warpAffine(img_05, M05, (W, H), flags=cv2.INTER_CUBIC, borderValue=(255, 255, 255))
    all_raw["05_pure_innocence"] = attach_head_neck_blend(img_05, rot_05)

    # 08_deep_confusion:
    b16_for_08 = warp_grid(refs["16"], lambda gx, gy: (
        24.0 * np.exp(-((gy - 275.0) / 85.0)**2) * np.exp(-((gx - 340.0) / 65.0)**2),
        28.0 * np.exp(-((gy - 275.0) / 95.0)**2) * np.exp(-((gx - 335.0) / 75.0)**2)
    ))
    base_08 = make_left_arm_raised_base(b16_for_08, refs["07"], split_x=376)
    img_08 = attach_head_neck_blend(base_08, faces_17["08_deep_confusion"])
    hand_mask_08 = np.zeros((H, W), dtype=np.float32)
    hand_mask_08[254:345, 325:376] = 1.0
    hand_mask_08 = cv2.GaussianBlur(hand_mask_08, (0, 0), 3.0)
    img_08 = (img_08.astype(np.float32) * (1.0 - hand_mask_08[:, :, None]) + base_08.astype(np.float32) * hand_mask_08[:, :, None]).astype(np.uint8)
    all_raw["08_deep_confusion"] = img_08

    # 09_suspicious_glare:
    img_09 = attach_head_neck_blend(refs["03"], faces_17["09_suspicious_glare"])
    all_raw["09_suspicious_glare"] = warp_grid(img_09, lambda gx, gy: (
        -3.0 * np.clip((700.0 - gy) / 400.0, 0.0, 1.0),
        -2.0 * np.clip((700.0 - gy) / 400.0, 0.0, 1.0)
    ))

    # 10_bored_apathy:
    img_10 = attach_head_neck_blend(refs["07"], faces_17["10_bored_apathy"])
    all_raw["10_bored_apathy"] = warp_grid(img_10, lambda gx, gy: (
        np.zeros_like(gx),
        9.0 * np.exp(-((gy - 350.0) / 220.0)**2)
    ))

    # 14_quiet_melancholy:
    img_14 = attach_head_neck_blend(refs["07"], faces_17["14_quiet_melancholy"])
    all_raw["14_quiet_melancholy"] = warp_grid(img_14, lambda gx, gy: (
        -4.0 * np.sign(gx - 382.0) * np.exp(-((gy - 520.0) / 180.0)**2),
        8.0 * np.exp(-((gy - 340.0) / 220.0)**2)
    ))

    # 15_tearful_sorrow:
    b16_for_15 = warp_grid(refs["16"], lambda gx, gy: (
        6.0 * np.exp(-((gy - 250.0) / 80.0)**2) * np.exp(-((gx - 340.0) / 60.0)**2),
        18.0 * np.exp(-((gy - 260.0) / 95.0)**2) * np.exp(-((gx - 330.0) / 75.0)**2)
    ))
    base_15 = make_left_arm_raised_base(b16_for_15, refs["07"], split_x=376)
    img_15 = attach_head_neck_blend(base_15, faces_17["15_tearful_sorrow"])
    hand_mask_15 = np.zeros((H, W), dtype=np.float32)
    hand_mask_15[224:345, 312:362] = 1.0
    hand_mask_15 = cv2.GaussianBlur(hand_mask_15, (0, 0), 3.0)
    img_15 = (img_15.astype(np.float32) * (1.0 - hand_mask_15[:, :, None]) + base_15.astype(np.float32) * hand_mask_15[:, :, None]).astype(np.uint8)
    all_raw["15_tearful_sorrow"] = img_15

    # 18_visceral_disgust:
    base_18 = make_left_arm_raised_base(refs["11"], refs["07"], split_x=376)
    img_18 = attach_head_neck_blend(base_18, faces_17["18_visceral_disgust"])
    all_raw["18_visceral_disgust"] = warp_grid(img_18, lambda gx, gy: (
        5.0 * np.exp(-((gy - 340.0) / 220.0)**2),
        -2.0 * np.exp(-((gy - 340.0) / 220.0)**2)
    ))

    # 19_desperate_pleading:
    base_19 = warp_grid(refs["01"], lambda gx, gy: (
        np.zeros_like(gx),
        -15.0 * np.exp(-((gy - 415.0) / 75.0)**2) * np.exp(-((gx - 382.0) / 95.0)**2)
    ))
    all_raw["19_desperate_pleading"] = attach_head_neck_blend(base_19, faces_17["19_desperate_pleading"])

    # 20_paralyzing_terror:
    base_20 = warp_grid(refs["03"], lambda gx, gy: (
        -12.0 * np.sign(gx - 382.0) * np.exp(-((gy - 430.0) / 110.0)**2),
        -7.0 * np.exp(-((gy - 445.0) / 95.0)**2)
    ))
    all_raw["20_paralyzing_terror"] = attach_head_neck_blend(base_20, faces_17["20_paralyzing_terror"])

    # 23_hollow_dead_eyed_void:
    img_23 = attach_head_neck_blend(refs["07"], faces_17["23_hollow_dead_eyed_void"])
    all_raw["23_hollow_dead_eyed_void"] = warp_grid(img_23, lambda gx, gy: (
        -4.0 * np.sign(gx - 382.0) * np.exp(-((gy - 520.0) / 180.0)**2),
        9.0 * np.exp(-((gy - 360.0) / 220.0)**2) + 4.0 * np.clip((gx - 382.0) / 150.0, -1.0, 1.0) * np.exp(-((gy - 320.0) / 180.0)**2)
    ))

    # 24_obsessive_yandere_blush:
    img_24 = faces_17["24_obsessive_yandere_blush"].copy()
    r01_shifted = np.roll(refs["01"], 4, axis=0)
    chin_m24 = np.zeros((H, W), dtype=np.float32)
    chin_m24[256:283, 355:409] = 1.0
    chin_m24 = cv2.GaussianBlur(chin_m24, (0, 0), 2.5)[:, :, None]
    img_24 = (img_24.astype(np.float32) * (1.0 - chin_m24) + r01_shifted.astype(np.float32) * chin_m24).astype(np.uint8)
    cv2.line(img_24, (393, 248), (393, 260), (242, 225, 248), 3, cv2.LINE_AA)
    cv2.line(img_24, (393, 248), (393, 260), (255, 255, 255), 1, cv2.LINE_AA)
    cv2.circle(img_24, (393, 261), 2, (255, 255, 255), -1, cv2.LINE_AA)
    all_raw["24_obsessive_yandere_blush"] = img_24

    # 25_shadowed_psychosis:
    all_raw["25_shadowed_psychosis"] = attach_head_neck_blend(refs["07"], faces_17["25_shadowed_psychosis"])

    # 27_bloodstained_innocence:
    b07_src = refs["07"].copy()
    central_body = b07_src.copy()
    for y in range(308, 825):
        row = b07_src[y]
        if y < 500:
            l_navy = np.where((row[:, 0] < 135) & (row[:, 1] < 135) & (np.arange(W) >= 275) & (np.arange(W) <= 330))[0]
            xl = l_navy[0] if len(l_navy) > 0 else 295
            if y < 345:
                r_body = np.where((row[:, 2] < 115) & (np.arange(W) >= 435) & (np.arange(W) <= 482))[0]
            else:
                r_body = np.where((row[:, 1] < 175) & (np.arange(W) >= 435) & (np.arange(W) <= 495))[0]
            xr = r_body[-1] if len(r_body) > 0 else 474
            central_body[y, :max(xl, 252 if 644 <= y <= 656 else xl)] = 255
            central_body[y, xr+1:] = 255
        elif y < 568:
            xl = 250
            for x in range(330, 150, -1):
                if row[x, 0] > 242 and row[x, 1] > 242 and row[x, 2] > 242:
                    xl = x
                    break
            # Keep both dark navy waistband/bow (R < 145) AND lavender braid tail ((B - R >= 14) & (R < 205))
            is_dress_or_braid = (row[:, 2] < 145) | (((row[:, 0].astype(int) - row[:, 2].astype(int)) >= 14) & (row[:, 2] < 205))
            r_navy = np.where(is_dress_or_braid & (np.arange(W) >= 425) & (np.arange(W) <= 472))[0]
            xr = r_navy[-1] if len(r_navy) > 0 else 464
            central_body[y, :max(xl, 252 if 644 <= y <= 656 else xl)] = 255
            central_body[y, xr+1:] = 255
        else:
            xl = 250
            for x in range(330, 150, -1):
                if row[x, 0] > 242 and row[x, 1] > 242 and row[x, 2] > 242:
                    xl = x
                    break
            xr = 520
            for x in range(468, 620):
                if row[x, 0] > 240 and row[x, 1] > 240 and row[x, 2] > 240:
                    xr = x
                    break
            central_body[y, :max(xl, 252 if 644 <= y <= 656 else xl)] = 255
            central_body[y, xr+1:] = 255

    # Fill the 12px right-skirt notch at y=515..570, x=445..490 where 07's right sleeve overlapped the skirt edge,
    # by mirroring the clean left navy waistband/skirt edge (x=276..321 -> 445..490) underneath the lavender braid tail!
    for y in range(512, 572):
        for x in range(445, 490):
            # Only fill if central_body[y, x] was erased to white (>240)
            if central_body[y, x, 0] > 240 and central_body[y, x, 1] > 240 and central_body[y, x, 2] > 240:
                mirror_x = 766 - x
                central_body[y, x] = central_body[y, mirror_x]

    from test_fix_27_and_12 import sleeves_27, splatters_torso
    sleeves_27_sym = sleeves_27.copy()
    sleeves_27_sym[310:495, 434:534] = sleeves_27[310:495, 230:330][:, ::-1]
    sleeves_27_sym[495:, 434:] = 255
    cb_mask = get_closed_character_silhouette(central_body)
    cb_mask_f = cv2.GaussianBlur(cb_mask.astype(np.float32), (0, 0), 1.0)
    base_27 = (sleeves_27_sym.astype(np.float32) * (1.0 - cb_mask_f[:, :, None]) + central_body.astype(np.float32) * cb_mask_f[:, :, None]).astype(np.uint8)
    overlay_27 = base_27.copy()
    for sx, sy, r1, r2, ang in splatters_torso:
        cv2.ellipse(overlay_27, (sx, sy), (r1, r2), ang, 0, 360, (32, 20, 165), -1, cv2.LINE_AA)
    base_27 = cv2.addWeighted(overlay_27, 0.85, base_27, 0.15, 0)
    all_raw["27_bloodstained_innocence"] = attach_head_neck_blend(base_27, faces_17["27_bloodstained_innocence"])

    # 28_manic_finger_biting:
    b16_for_28 = warp_grid(refs["16"], lambda gx, gy: (
        28.0 * np.exp(-((gy - 255.0) / 85.0)**2) * np.exp(-((gx - 340.0) / 65.0)**2),
        16.0 * np.exp(-((gy - 265.0) / 95.0)**2) * np.exp(-((gx - 335.0) / 75.0)**2)
    ))
    base_28 = make_left_arm_raised_base(b16_for_28, refs["07"], split_x=376)
    img_28 = attach_head_neck_blend(base_28, faces_17["28_manic_finger_biting"])
    hand_mask_28 = np.zeros((H, W), dtype=np.float32)
    hand_mask_28[250:345, 325:374] = 1.0
    hand_mask_28 = cv2.GaussianBlur(hand_mask_28, (0, 0), 2.5)
    img_28 = (img_28.astype(np.float32) * (1.0 - hand_mask_28[:, :, None]) + base_28.astype(np.float32) * hand_mask_28[:, :, None]).astype(np.uint8)
    all_raw["28_manic_finger_biting"] = img_28

    # 29_glitching_distortion:
    base_29 = refs["26"].copy()
    rng = np.random.RandomState(290)
    for _ in range(10):
        gy = rng.randint(330, 680)
        gh = rng.choice([2, 4, 6])
        shift = rng.choice([-10, -6, 6, 10])
        base_29[gy:gy+gh, :] = np.roll(base_29[gy:gy+gh, :], shift, axis=1)
    all_raw["29_glitching_distortion"] = attach_head_neck_blend(base_29, faces_17["29_glitching_distortion"])

    # 30_predatory_bloodlust:
    f30_clean = faces_17["30_predatory_bloodlust"].copy()
    r01_s3 = np.roll(refs["01"], 3, axis=0)
    chin_m30 = np.zeros((H, W), dtype=np.float32)
    chin_m30[256:281, 358:406] = 1.0
    chin_m30 = cv2.GaussianBlur(chin_m30, (0, 0), 2.2)[:, :, None]
    f30_clean = (f30_clean.astype(np.float32) * (1.0 - chin_m30) + r01_s3.astype(np.float32) * chin_m30).astype(np.uint8)
    img_30_raw = attach_head_neck_blend(refs["26"], f30_clean)
    img_30_raw = warp_grid(img_30_raw, lambda gx, gy: (
        (gx - 382.0) * (-0.04 * np.exp(-((gy - 300.0) / 220.0)**2)),
        10.0 * np.exp(-((gy - 280.0) / 220.0)**2)
    ))
    all_raw["30_predatory_bloodlust"] = img_30_raw

    return all_raw

if __name__ == "__main__":
    all_raw = build_all_30_raw_bodies()
    rebuilt = {}
    for k in sorted(all_raw.keys()):
        raw = all_raw[k]
        sh = apply_boutique_pixel_shader(raw, k)
        if k.startswith("30"):
            sil = get_closed_character_silhouette(raw, thresh=240)
            sh = apply_dithered_aura_30(sh, sil)
        if k != "00_base_reference":
            decorate_state_pixel_accents(sh, k)
        rebuilt[k] = sh

        # Save to workspace:
        if k == "00_base_reference":
            cv2.imwrite(os.path.join(WORK_DIR, "00_base_reference.png"), sh)
            cv2.imwrite(os.path.join(PNG_DIR, "00_base_reference.png"), sh)
            cv2.imwrite(os.path.join(ART_DIR, "00_base_reference.png"), sh)
        else:
            jpg_path = os.path.join(WORK_DIR, f"{k}.jpg")
            png_path = os.path.join(PNG_DIR, f"{k}.png")
            art_jpg_path = os.path.join(ART_DIR, f"{k}.jpg")
            cv2.imwrite(jpg_path, sh, [int(cv2.IMWRITE_JPEG_QUALITY), 98])
            cv2.imwrite(png_path, sh)
            cv2.imwrite(art_jpg_path, sh, [int(cv2.IMWRITE_JPEG_QUALITY), 98])
        print("Rebuilt & saved:", k)

    # Build 2 high-res verification sheets of all 30 states (01..15 and 16..30)
    state_keys = [k for k in sorted(rebuilt.keys()) if k != "00_base_reference"]
    for part_idx, chunk in enumerate([state_keys[:15], state_keys[15:]], start=1):
        cols, rows = 5, 3
        cw, ch = 460, 620
        sheet = np.full((rows * ch, cols * cw, 3), 245, dtype=np.uint8)
        for i, k in enumerate(chunk):
            r, c = divmod(i, cols)
            # Show upper body + face + pixel accents (y=55..760, x=150..615)
            crop = rebuilt[k][55:760, 150:615]
            crop_r = cv2.resize(crop, (cw, ch), interpolation=cv2.INTER_AREA)
            cv2.putText(crop_r, k, (12, ch - 14), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (30, 20, 160), 2, cv2.LINE_AA)
            sheet[r*ch:(r+1)*ch, c*cw:(c+1)*cw] = crop_r
        sp = os.path.join(SCRATCH_DIR, f"all_30_rebuilt_part{part_idx}.png")
        cv2.imwrite(sp, sheet)
        print("Saved contact sheet:", sp)
