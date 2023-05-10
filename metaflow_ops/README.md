# Use conda

```
conda install -c conda-forge poetry
conda create -n metaflow_ops python=3.9
conda activate metaflow_ops

pip install -r requirements.txt

```


# Use poetry + venv

``` bash
source "$( poetry env list --full-path | grep Activated | cut -d' ' -f1 )/bin/activate"

poetry install
```


## Running 

-- Example 1: `python example_01.py run`
-- Example 2: `python example_02_tags.py run --tag team_id:1 --tag version:1`
