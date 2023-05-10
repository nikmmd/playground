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


python example_01.py run --namespace my_namespace
