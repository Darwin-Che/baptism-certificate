import time

class Timer:
    def __init__(self):
        self.start = time.perf_counter()
        self.steps = {}

    def mark(self, name):
        now = time.perf_counter()
        self.steps[name] = round(now - self.start, 4)
        self.start = now
