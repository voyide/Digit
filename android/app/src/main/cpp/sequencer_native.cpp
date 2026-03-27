#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <cmath>
#include <cstdio>
#include <array>
#include <algorithm>
#include <zlib.h>

extern "C" {

struct RenderRequest {
  uint64_t start_n;
  int32_t b_num;
  int32_t render_r;
  int32_t render_c;
  int32_t logical_r;
  int32_t logical_c;
  int32_t mod_m;
  int32_t lhs_rule;
  int32_t rhs1_rule;
  int32_t rhs2_rule;
  int32_t logic_op;
  int32_t post_type;
  int32_t iter_k;
  int32_t post_grid_r;
  int32_t post_grid_c;
  int32_t target_t;
  int32_t mod_mc;
  int32_t tuple_k;
  int32_t row_start;
  int32_t row_end;
};

static inline int iabs32(int x) { return x < 0 ? -x : x; }

static inline int safe_base(int b) { return b < 2 ? 2 : b; }
static inline int safe_mod(int m) { return m < 1 ? 1 : m; }
static inline int safe_tuple_k(int k) { return k < 1 ? 1 : k; }

static inline int gcd_i(int a, int b) {
  while (b != 0) {
    int t = b;
    b = a % b;
    a = t;
  }
  return a;
}

static inline int eval_lhs(int rule, int xi, int xNext, int b, int di, int dNext) {
  switch (rule) {
    case 0: return iabs32(xi - xNext);
    case 2: return (xNext - xi + b) % b;
    case 3: return (xi + xNext) % b;
    case 4: return xi > xNext ? xi : xNext;
    case 5: return xi < xNext ? xi : xNext;
    case 6: return (xi ^ xNext) % b;
    case 8: return (xi * xNext) % b;
    case 9: return iabs32((b - 1 - xi) - xNext);
    case 12: return iabs32(((xi * xi) % b) - xNext);
    case 19: return ((xi * xi * xi) + (xNext * xNext * xNext)) % b;
    case 20: return iabs32((xi * xi) - (xNext * xNext));
    case 21: return gcd_i(xi, xNext);
    case 22: {
      int g = gcd_i(xi, xNext);
      return g == 0 ? 0 : ((xi * xNext) / g) % b;
    }
    case 23: return iabs32(xi - (b / 2)) + iabs32(xNext - (b / 2));
    case 24: return (xi | xNext) % b;
    case 25: return (xi & xNext) % b;
    case 26: return ((xi << 1) ^ xNext) % b;
    case 27: return ((xi * (xi + 1)) / 2) % b;
    case 28: return ((xi * xi) + (xi * xNext) + (xNext * xNext)) % b;
    case 29: return ((xi * di) + (xNext * dNext)) % b;
    case 30: return ((xi + 1) * (xNext + 1)) % b;
    default: return iabs32(xi - xNext);
  }
}

static inline bool eval_rhs(int rule, int val, int di, int dNext, int b) {
  switch (rule) {
    case 0: return val == di;
    case 1: return val == (b - 1 - di);
    case 2: return val <= di;
    case 3: return val >= di;
    case 4: return val != di;
    case 5: return (val % 2) == (di % 2);
    case 6: return val == (b / 2);
    case 7: return val < di;
    case 8: return val > di;
    case 9: return val == (di + 1) % b;
    case 10: return val == (di + dNext) % b;
    case 11: return val == (di * dNext) % b;
    case 12: return (val % 3) == (di % 3);
    case 13: return (val % 4) == (di % 4);
    case 14: return val == ((di * di) % b);
    case 15: return val == iabs32(di - dNext);
    case 16: return val == (di > dNext ? di : dNext);
    case 17: return val == (di < dNext ? di : dNext);
    case 18: return val == (di ^ dNext);
    case 19: return val > (b / 2);
    case 20: return val < (b / 2);
    case 21: return val == (b - di) % b;
    case 22: return val != (di + 1) % b;
    case 23: return val <= (di + (b / 2)) % b;
    case 24: return val >= (di - (b / 2)) % b;
    default: return val == di;
  }
}

struct DigitCursor {
  int b = 2;
  int k = 1;
  int digits[128]{};

  explicit DigitCursor(int base) : b(base) {}

  void set_u64(uint64_t n) {
    if (n == 0) {
      k = 1;
      digits[1] = 0;
      return;
    }

    uint64_t t = n;
    int len = 0;
    while (t > 0) {
      len++;
      t /= static_cast<uint64_t>(b);
    }
    k = len;

    t = n;
    for (int i = k; i >= 1; --i) {
      digits[i] = static_cast<int>(t % static_cast<uint64_t>(b));
      t /= static_cast<uint64_t>(b);
    }
  }

  inline int digit_at(int i) const {
    if (i <= k) return digits[i];
    return digits[((i - 1) % k) + 1];
  }

  void increment() {
    if (k == 1 && digits[1] == 0) {
      digits[1] = 1;
      return;
    }

    int pos = k;
    while (pos >= 1 && digits[pos] == b - 1) {
      digits[pos] = 0;
      pos--;
    }

    if (pos >= 1) {
      digits[pos]++;
      return;
    }

    k++;
    digits[1] = 1;
    for (int i = 2; i <= k; ++i) digits[i] = 0;
  }
};

struct Runtime {
  const RenderRequest* req = nullptr;
  int b = 2;
  int tupleK = 1;
  bool isGlobal14 = false;
  int stateCount = 0;
  std::vector<int32_t> initVec;
  std::vector<int32_t> offsets;
  std::vector<int32_t> succ;

  explicit Runtime(const RenderRequest* r) : req(r) {
    b = safe_base(r->b_num);
    tupleK = safe_tuple_k(r->tuple_k);
    isGlobal14 = r->lhs_rule == 14;
  }

  inline bool accept(int val, int di, int dNext) const {
    bool c1 = eval_rhs(req->rhs1_rule, val, di, dNext, b);
    if (req->logic_op == 2) {
      return c1 || eval_rhs(req->rhs2_rule, val, di, dNext, b);
    }
    return c1;
  }

  bool build() {
    if (b > 48) return false;

    if (isGlobal14) {
      stateCount = 0;
      return true;
    }

    if (req->lhs_rule == 1 || req->lhs_rule == 10 || req->lhs_rule == 11 ||
        (req->lhs_rule >= 15 && req->lhs_rule <= 18)) {
      if (b > 36) return false;
      stateCount = b * b;
    } else {
      stateCount = b;
    }

    initVec.assign(stateCount, 1);

    if (req->lhs_rule == 1) {
      std::fill(initVec.begin(), initVec.end(), 0);
      for (int x1 = 0; x1 < b; ++x1) {
        initVec[x1 * b + x1] = 1;
      }
    }

    const int pairCount = b * b;
    offsets.assign(pairCount * stateCount + 1, 0);

    std::vector<int32_t> flat;
    flat.reserve(pairCount * stateCount * std::max(2, b / 2));

    int off = 0;

    for (int pair = 0; pair < pairCount; ++pair) {
      const int di = pair / b;
      const int dNext = pair % b;

      for (int state = 0; state < stateCount; ++state) {
        offsets[off++] = static_cast<int32_t>(flat.size());

        if (req->lhs_rule == 1) {
          int x1 = state / b;
          for (int xNext = 0; xNext < b; ++xNext) {
            int val = iabs32(x1 - xNext);
            if (accept(val, di, dNext)) {
              flat.push_back(x1 * b + xNext);
            }
          }
        } else if (req->lhs_rule == 7) {
          int acc = state;
          for (int xNext = 0; xNext < b; ++xNext) {
            int val = iabs32(acc - xNext);
            if (accept(val, di, dNext)) {
              flat.push_back(val);
            }
          }
        } else if (req->lhs_rule == 10 || req->lhs_rule == 11) {
          int a = state / b;
          int bVal = state % b;
          for (int c = 0; c < b; ++c) {
            int val = (req->lhs_rule == 10)
                          ? iabs32(iabs32(a - bVal) - iabs32(bVal - c))
                          : iabs32(a - bVal - c);

            if (accept(val, di, dNext)) {
              flat.push_back(bVal * b + c);
            }
          }
        } else if (req->lhs_rule >= 15 && req->lhs_rule <= 18) {
          int xiX = state % b;
          int xiY = state / b;
          for (int nextState = 0; nextState < stateCount; ++nextState) {
            int xNextX = nextState % b;
            int xNextY = nextState / b;
            double dx = static_cast<double>(xiX - xNextX);
            double dy = static_cast<double>(xiY - xNextY);
            double dist = std::sqrt(dx * dx + dy * dy);
            int val = 0;

            if (req->lhs_rule == 15) val = static_cast<int>(dist);
            if (req->lhs_rule == 16) val = static_cast<int>(std::floor(dist));
            if (req->lhs_rule == 17) val = static_cast<int>(std::ceil(dist));
            if (req->lhs_rule == 18) val = static_cast<int>(std::llround(dist));

            if (accept(val, di, dNext)) {
              flat.push_back(nextState);
            }
          }
        } else {
          int xi = state;
          for (int xNext = 0; xNext < b; ++xNext) {
            int val = eval_lhs(req->lhs_rule, xi, xNext, b, di, dNext);
            if (accept(val, di, dNext)) {
              flat.push_back(xNext);
            }
          }
        }
      }
    }

    offsets[off] = static_cast<int32_t>(flat.size());
    succ.swap(flat);
    return true;
  }
};

static int solve_global14_mod(const RenderRequest& req, DigitCursor& cursor, int mod) {
  const int b = safe_base(req.b_num);
  const int loopEnd = std::max(1, cursor.k + safe_tuple_k(req.tuple_k) - 1);
  const int L = loopEnd + 1;
  const int maxSum = L * (b - 1);

  std::vector<int32_t> dp(maxSum + 1, 0);
  std::vector<int32_t> nextDp(maxSum + 1, 0);

  int totalWays = 0;

  for (int x1 = 0; x1 < b; ++x1) {
    for (int sigma = x1; sigma <= maxSum; ++sigma) {
      std::fill(dp.begin(), dp.end(), 0);
      dp[x1] = 1;
      bool possible = true;

      for (int i = 1; i <= loopEnd; ++i) {
        const int di = cursor.digit_at(i);
        const int dNext = cursor.digit_at(i + 1);

        std::fill(nextDp.begin(), nextDp.end(), 0);
        bool hasState = false;

        for (int ci = x1; ci <= sigma; ++ci) {
          const int ways = dp[ci];
          if (ways == 0) continue;

          for (int xNext = 0; xNext < b; ++xNext) {
            const int pi = 2 * x1 - ci;
            const int si = 2 * xNext + ci - sigma;
            const int val = iabs32(iabs32(pi) - iabs32(si));

            bool c1 = eval_rhs(req.rhs1_rule, val, di, dNext, b);
            bool ok = c1;
            if (req.logic_op == 2) {
              ok = c1 || eval_rhs(req.rhs2_rule, val, di, dNext, b);
            }

            if (ok) {
              const int nextC = ci + xNext;
              if (nextC <= sigma) {
                int nv = nextDp[nextC] + ways;
                if (nv >= mod) nv %= mod;
                nextDp[nextC] = nv;
                hasState = true;
              }
            }
          }
        }

        if (!hasState) {
          possible = false;
          break;
        }

        dp.swap(nextDp);
      }

      if (possible) {
        totalWays += dp[sigma];
        if (totalWays >= mod) totalWays %= mod;
      }
    }
  }

  return totalWays % mod;
}

struct Runner {
  const Runtime& rt;
  DigitCursor cursor;
  std::vector<int32_t> a;
  std::vector<int32_t> bvec;

  explicit Runner(const Runtime& runtime)
      : rt(runtime), cursor(runtime.b), a(std::max(1, runtime.stateCount), 0),
        bvec(std::max(1, runtime.stateCount), 0) {}

  int solve_mod_u64(uint64_t n, int mod) {
    cursor.set_u64(n);
    return solve_current_mod(mod);
  }

  int solve_current_mod(int mod) {
    const int safeM = safe_mod(mod);
    if (safeM == 1) return 0;

    if (rt.isGlobal14) {
      return solve_global14_mod(*rt.req, cursor, safeM);
    }

    for (int i = 0; i < rt.stateCount; ++i) {
      a[i] = rt.initVec[i];
    }

    const int loopEnd = std::max(1, cursor.k + rt.tupleK - 1);

    for (int i = 1; i <= loopEnd; ++i) {
      const int pair = cursor.digit_at(i) * rt.b + cursor.digit_at(i + 1);
      std::fill(bvec.begin(), bvec.end(), 0);

      const int base = pair * rt.stateCount;
      for (int state = 0; state < rt.stateCount; ++state) {
        const int ways = a[state];
        if (ways == 0) continue;

        const int start = rt.offsets[base + state];
        const int end = rt.offsets[base + state + 1];

        for (int p = start; p < end; ++p) {
          const int ns = rt.succ[p];
          int nv = bvec[ns] + ways;
          if (nv >= safeM) nv %= safeM;
          bvec[ns] = nv;
        }
      }

      a.swap(bvec);
    }

    int total = 0;
    for (int i = 0; i < rt.stateCount; ++i) {
      total += a[i];
      if (total >= safeM) total %= safeM;
    }
    return total % safeM;
  }
};

static inline void write_rgba(uint8_t* dst, int idx, uint32_t rgb) {
  dst[idx] = static_cast<uint8_t>((rgb >> 16) & 0xFF);
  dst[idx + 1] = static_cast<uint8_t>((rgb >> 8) & 0xFF);
  dst[idx + 2] = static_cast<uint8_t>(rgb & 0xFF);
  dst[idx + 3] = 255;
}

static int render_rows_rgba_internal(
    const RenderRequest& req,
    const uint32_t* palette,
    uint8_t* out_rgba,
    int64_t out_len) {

  if (req.post_type != 0) return -3;
  if (req.render_r <= 0 || req.render_c <= 0) return -1;
  if (req.row_start < 0 || req.row_end < req.row_start || req.row_end > req.render_r) return -1;

  const int rows = req.row_end - req.row_start;
  const int64_t needed = static_cast<int64_t>(rows) * req.render_c * 4;
  if (out_len < needed) return -2;

  Runtime rt(&req);
  if (!rt.build()) return -4;
  Runner runner(rt);

  const bool identity =
      req.render_r == req.logical_r &&
      req.render_c == req.logical_c &&
      req.post_type == 0;

  int64_t p = 0;

  if (identity) {
    uint64_t n0 = req.start_n + static_cast<uint64_t>(req.row_start) * static_cast<uint64_t>(req.render_c);
    runner.cursor.set_u64(n0);

    for (int r = req.row_start; r < req.row_end; ++r) {
      for (int c = 0; c < req.render_c; ++c) {
        int modVal = runner.solve_current_mod(safe_mod(req.mod_m));
        uint32_t color = palette[modVal % safe_mod(req.mod_m)];
        write_rgba(out_rgba, static_cast<int>(p), color);
        p += 4;

        if (!(r == req.row_end - 1 && c == req.render_c - 1)) {
          runner.cursor.increment();
        }
      }
    }

    return 0;
  }

  for (int r = req.row_start; r < req.row_end; ++r) {
    int srcR = static_cast<int>((static_cast<int64_t>(r) * req.logical_r) / req.render_r);
    int64_t rowBase = static_cast<int64_t>(srcR) * req.logical_c;

    for (int c = 0; c < req.render_c; ++c) {
      int srcC = static_cast<int>((static_cast<int64_t>(c) * req.logical_c) / req.render_c);
      uint64_t n = req.start_n + static_cast<uint64_t>(rowBase + srcC);
      int modVal = runner.solve_mod_u64(n, safe_mod(req.mod_m));
      uint32_t color = palette[modVal % safe_mod(req.mod_m)];
      write_rgba(out_rgba, static_cast<int>(p), color);
      p += 4;
    }
  }

  return 0;
}

static void write_u32_be(FILE* fp, uint32_t v) {
  uint8_t b[4] = {
      static_cast<uint8_t>((v >> 24) & 0xFF),
      static_cast<uint8_t>((v >> 16) & 0xFF),
      static_cast<uint8_t>((v >> 8) & 0xFF),
      static_cast<uint8_t>(v & 0xFF),
  };
  fwrite(b, 1, 4, fp);
}

static bool write_chunk(FILE* fp, const char type[4], const uint8_t* data, uint32_t len) {
  write_u32_be(fp, len);
  fwrite(type, 1, 4, fp);
  if (len > 0 && data != nullptr) {
    fwrite(data, 1, len, fp);
  }

  uLong crc = crc32(0L, Z_NULL, 0);
  crc = crc32(crc, reinterpret_cast<const Bytef*>(type), 4);
  if (len > 0 && data != nullptr) {
    crc = crc32(crc, reinterpret_cast<const Bytef*>(data), len);
  }
  write_u32_be(fp, static_cast<uint32_t>(crc));
  return true;
}

static int render_png_file_internal(const RenderRequest& req, const uint32_t* palette, const char* path) {
  if (req.post_type != 0) return -3;
  if (req.render_r <= 0 || req.render_c <= 0) return -1;
  if (req.logical_r != req.render_r || req.logical_c != req.render_c) return -5;

  Runtime rt(&req);
  if (!rt.build()) return -4;
  Runner runner(rt);

  FILE* fp = fopen(path, "wb");
  if (!fp) return -6;

  const uint8_t signature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
  fwrite(signature, 1, 8, fp);

  uint8_t ihdr[13];
  ihdr[0] = static_cast<uint8_t>((req.render_c >> 24) & 0xFF);
  ihdr[1] = static_cast<uint8_t>((req.render_c >> 16) & 0xFF);
  ihdr[2] = static_cast<uint8_t>((req.render_c >> 8) & 0xFF);
  ihdr[3] = static_cast<uint8_t>(req.render_c & 0xFF);
  ihdr[4] = static_cast<uint8_t>((req.render_r >> 24) & 0xFF);
  ihdr[5] = static_cast<uint8_t>((req.render_r >> 16) & 0xFF);
  ihdr[6] = static_cast<uint8_t>((req.render_r >> 8) & 0xFF);
  ihdr[7] = static_cast<uint8_t>(req.render_r & 0xFF);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  write_chunk(fp, "IHDR", ihdr, 13);

  z_stream zs{};
  if (deflateInit(&zs, Z_BEST_SPEED) != Z_OK) {
    fclose(fp);
    return -7;
  }

  std::vector<uint8_t> row(1 + req.render_c * 4);
  std::array<uint8_t, 32768> zbuf{};

  runner.cursor.set_u64(req.start_n);

  for (int r = 0; r < req.render_r; ++r) {
    row[0] = 0;
    int p = 1;

    for (int c = 0; c < req.render_c; ++c) {
      int modVal = runner.solve_current_mod(safe_mod(req.mod_m));
      uint32_t color = palette[modVal % safe_mod(req.mod_m)];
      row[p++] = static_cast<uint8_t>((color >> 16) & 0xFF);
      row[p++] = static_cast<uint8_t>((color >> 8) & 0xFF);
      row[p++] = static_cast<uint8_t>(color & 0xFF);
      row[p++] = 255;

      if (!(r == req.render_r - 1 && c == req.render_c - 1)) {
        runner.cursor.increment();
      }
    }

    zs.next_in = row.data();
    zs.avail_in = static_cast<uInt>(row.size());

    while (zs.avail_in > 0) {
      zs.next_out = zbuf.data();
      zs.avail_out = static_cast<uInt>(zbuf.size());
      int ret = deflate(&zs, Z_NO_FLUSH);
      if (ret != Z_OK) {
        deflateEnd(&zs);
        fclose(fp);
        return -8;
      }
      uint32_t produced = static_cast<uint32_t>(zbuf.size() - zs.avail_out);
      if (produced > 0) {
        write_chunk(fp, "IDAT", zbuf.data(), produced);
      }
    }
  }

  int flushRet;
  do {
    zs.next_out = zbuf.data();
    zs.avail_out = static_cast<uInt>(zbuf.size());
    flushRet = deflate(&zs, Z_FINISH);
    uint32_t produced = static_cast<uint32_t>(zbuf.size() - zs.avail_out);
    if (produced > 0) {
      write_chunk(fp, "IDAT", zbuf.data(), produced);
    }
  } while (flushRet == Z_OK);

  deflateEnd(&zs);

  if (flushRet != Z_STREAM_END) {
    fclose(fp);
    return -9;
  }

  write_chunk(fp, "IEND", nullptr, 0);
  fclose(fp);
  return 0;
}

__attribute__((visibility("default")))
int render_stripe_rgba(
    const RenderRequest* req,
    const uint32_t* palette,
    uint8_t* out_rgba,
    int64_t out_len) {
  if (req == nullptr || palette == nullptr || out_rgba == nullptr) return -1;
  return render_rows_rgba_internal(*req, palette, out_rgba, out_len);
}

__attribute__((visibility("default")))
int render_png_file(
    const RenderRequest* req,
    const uint32_t* palette,
    const char* path_utf8) {
  if (req == nullptr || palette == nullptr || path_utf8 == nullptr) return -1;
  return render_png_file_internal(*req, palette, path_utf8);
}

} // extern "C"
