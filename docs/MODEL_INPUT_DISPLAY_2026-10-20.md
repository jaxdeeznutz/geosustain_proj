# Model inputs and farmer UI cleanup

Removed redundant automated-analysis and duplicate-farm explanations below the mapping screen. Retained a short saved-farm name, map attribution, area and vertices.

The saved Random Forest has ten features: N, P, K, temperature, humidity, ph, rainfall, ndvi, elevation, slope. The six-condition count refers to separate agronomic reference comparisons, not model inputs. Model-ranked cards no longer display that count; the factor panel now reads all ten values from recorded inference samples (arithmetic mean for parcels, unavailable if any sample is missing). Rainfall shown here is the 30-day model input, not annual reference rainfall. NPK estimates remain unchanged and are labelled as model estimates, not soil tests; no units were guessed and no retraining occurred.

Diagnostic: current augmented training CSV contains 260 rows for each of the seven catalog crops. Read-only predictions at each crop's training-feature median yielded these leading catalog crops: banana?banana 95.59%, coconut?coconut 45.12%, rice?rice 88.97%, durian?cacao 45.95%, mango?mango 36.16%, rubber?rubber 60.84%, cacao?cacao 67.21%. This is not validation accuracy or evidence for any specific farm. Rice does not always win. The durian/cacao overlap illustrates model limitations. Global importance: rainfall 18.85%; N/P/K combined 38.94%. Global importance does not explain an individual prediction. Actual repeated rice results need saved farm input snapshots to determine their cause.

Password policy now allows 8 or more characters, at most 72 UTF-8 bytes, with an ASCII punctuation symbol and no whitespace. Existing password login remains compatible.
