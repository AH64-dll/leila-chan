"""Build a llama.cpp control vector from the tweet's neurons: L14 N8949 +1, L13 N7956 -1.

Injecting dose*R/||W_down[:,n]|| into neuron n before down_proj adds dose*R*unit(W_down[:,n])
to that layer's output, so the control vector is the unit column; the runtime scale = dose*R.
Usage: python steer_build.py <model.gguf> <out.gguf>   (deps: requirements-experiments.txt)
"""
import sys
import numpy as np
import gguf
from gguf.quants import dequantize

NEURONS = [(14, 8949, +1.0), (13, 7956, -1.0)]

reader = gguf.GGUFReader(sys.argv[1])
tensors = {t.name: t for t in reader.tensors}
n_embd = int(reader.fields["qwen35.embedding_length"].contents())
n_layer = int(reader.fields["qwen35.block_count"].contents())

dirs = {}
for layer, n, sign in NEURONS:
    t = tensors[f"blk.{layer}.ffn_down.weight"]
    w = dequantize(t.data, t.tensor_type).reshape(n_embd, -1)  # (n_embd, n_ff)
    col = w[:, n].astype(np.float32)
    print(f"L{layer} N{n}: ||W_down[:,n]|| = {np.linalg.norm(col):.4f}")
    dirs[layer] = dirs.get(layer, np.zeros(n_embd, np.float32)) + sign * col / np.linalg.norm(col)

w = gguf.GGUFWriter(sys.argv[2], "controlvector")
w.add_string("controlvector.model_hint", "qwen35")
w.add_uint32("controlvector.layer_count", n_layer)
for layer, v in sorted(dirs.items()):
    w.add_tensor(f"direction.{layer}", v)
w.write_header_to_file(); w.write_kv_data_to_file(); w.write_tensors_to_file(); w.close()
print("wrote", sys.argv[2], {k: float(np.linalg.norm(v)) for k, v in dirs.items()})
