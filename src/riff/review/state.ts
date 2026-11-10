/** Evidence retained by the adapter, bounded independently of session length. */
import { Buffer } from 'node:buffer';
import { excerpt, type ReviewRequests, type ReviewResult } from './input.ts';

export class ReviewHistory {
  private current = '';
  private first: string | undefined;
  private recent: string[] = [];
  private results: ReviewResult[] = [];
  private omittedResults = 0;

  /** Starts a received prompt: earlier turns' tool results have no authority here. */
  prompt(text: string): void {
    if (this.first === undefined) {
      this.first = excerpt(text, 1024);
    } else if (this.current !== this.first) {
      this.recent.unshift(this.current);
    }

    this.current = excerpt(text, 1024);

    let remaining = 1024;

    this.recent = this.recent.flatMap((request) => {
      if (remaining === 0) {
        return [];
      }

      const kept = excerpt(request, remaining);

      remaining -= Buffer.byteLength(kept);

      return [kept];
    });

    this.results = [];
    this.omittedResults = 0;
  }

  /** Records only tool output, never assistant messages or permission feedback. */
  result(result: ReviewResult): void {
    this.results.unshift({
      id: excerpt(result.id, 512),
      tool: excerpt(result.tool, 512),
      text: excerpt(result.text, 1024),
    });

    let remaining = 8192;

    this.results = this.results.flatMap((entry, index) => {
      if (index >= 16 || remaining === 0) {
        this.omittedResults++;

        return [];
      }

      const text = excerpt(entry.text, remaining);

      remaining -= Buffer.byteLength(text);

      return [{ ...entry, text }];
    });
  }

  snapshot(): {
    readonly requests: ReviewRequests;
    readonly results: readonly ReviewResult[];
    readonly omittedResults: number;
  } {
    return {
      requests: {
        current: this.current,
        first: this.first ?? '',
        recent: [...this.recent],
      },
      results: [...this.results],
      omittedResults: this.omittedResults,
    };
  }
}
