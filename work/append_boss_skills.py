# -*- coding: utf-8 -*-
"""为 6 个 Boss 追加新技能配置（幂等，仅追加，不改旧技能参数）"""

import json

NEW_SKILLS = {
    "slime_king": [
        {"id": "split_self", "name": "????", "type": "split", "count": 2,
         "cooldown": 10.0, "windup": 0.6, "min_phase": 2},
    ],
    "tree_golem": [
        {"id": "root_spikes", "name": "????", "type": "spike_trail", "count": 6,
         "spacing": 64, "radius": 34, "delay": 0.6, "interval": 0.12, "damage_mult": 0.9,
         "cooldown": 9.0, "windup": 0.8, "telegraph": "dot", "min_phase": 1},
    ],
    "skeleton_king": [
        {"id": "bone_sweep", "name": "????", "type": "sweep",
         "duration": 1.6, "sweep_angle": 120,
         "cooldown": 10.0, "windup": 1.0, "telegraph": "line", "min_phase": 2},
    ],
    "imp_king": [
        {"id": "flame_spiral", "name": "????", "type": "spiral", "shots": 10,
         "bullet_speed": 160, "duration": 1.4, "ring_interval": 0.14, "offset": 18,
         "cooldown": 10.0, "windup": 0.9, "telegraph": "dot", "min_phase": 1},
        {"id": "fire_wall", "name": "????", "type": "wall", "count": 8,
         "radius": 46, "delay": 0.4, "interval": 0.12, "damage_mult": 1.0,
         "cooldown": 11.0, "windup": 0.9, "telegraph": "circle", "min_phase": 2},
    ],
    "ancient_guardian": [
        {"id": "seeker_light", "name": "????", "type": "homing_shot", "count": 4,
         "bullet_speed": 135, "turn_rate": 3.0, "lifetime": 4.0,
         "cooldown": 9.0, "windup": 0.8, "telegraph": "dot", "min_phase": 2},
        {"id": "guardian_blink", "name": "????", "type": "blink",
         "radius": 110, "damage_mult": 1.6,
         "cooldown": 10.0, "windup": 0.9, "telegraph": "circle", "min_phase": 1},
    ],
    "final_god": [
        {"id": "void_spiral", "name": "????", "type": "spiral", "shots": 12,
         "bullet_speed": 170, "duration": 1.8, "ring_interval": 0.12, "offset": 15,
         "cooldown": 10.0, "windup": 1.0, "telegraph": "dot", "min_phase": 2},
        {"id": "void_seeker", "name": "????", "type": "homing_shot", "count": 3,
         "bullet_speed": 140, "turn_rate": 3.0, "lifetime": 4.0,
         "cooldown": 12.0, "windup": 0.9, "telegraph": "dot", "min_phase": 3},
        {"id": "ancient_enrage", "name": "???", "type": "enrage",
         "speed_mult": 1.3, "cd_mult": 0.7,
         "cooldown": 0.5, "windup": 0.1, "min_phase": 3},
    ],
}


def main() -> None:
    path = r"data/enemies.json"
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    bosses = {b["id"]: b for b in data["bosses"]}
    added = 0
    for boss_id, skills in NEW_SKILLS.items():
        b = bosses[boss_id]
        existing = {s["id"] for s in b["skills"]}
        for sk in skills:
            if sk["id"] in existing:
                print("skip (exists):", boss_id, sk["id"])
                continue
            b["skills"].append(sk)
            added += 1
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("added:", added)
    for b in data["bosses"]:
        types = [s["type"] for s in b["skills"]]
        print(f"  {b['id']}: total={len(b['skills'])} types={types}")


if __name__ == "__main__":
    main()
